# Static asset deployment

This repository is a curated payload, not a general-purpose document root.
Deploy only the 105 files named by `asset-manifest.sha256`, `robots.txt`, and
the generated `release.json`. The JSON is release provenance, not a course
binary, so it must never be added to `asset-manifest.sha256` or committed.
Files listed in `PENDING.md` do not exist in the source library and must not be
fabricated, aliased to unrelated media, or added to a release.

## Server layout

The checked-in Nginx configuration assumes this release layout:

```text
/var/www/static.cs.avasan.org/
├── current -> releases/<commit>/
└── releases/
    └── <commit>/
        ├── assets.zip
        ├── ps*.gif / ps*.mp4
        ├── pyg_*.mp4
        ├── release.json
        └── robots.txt
```

`deploy/nginx/static.cs.avasan.org-assets.conf` is a server-context include for
the existing HTTPS virtual host. The existing virtual host should continue to
own its `listen`, `server_name`, certificate, access-log, and HTTP-to-HTTPS
redirect configuration. Install the include at a stable path, then reference
it from that HTTPS `server` block:

```nginx
include /etc/nginx/snippets/static.cs.avasan.org-assets.conf;
```

If the server must use a different document-root path, change the include's
single `root` directive and the release commands together. Do not retain a
second `root` directive in the surrounding server block.

The include:

- permits only root-level ZIP, GIF, and MP4 names, `robots.txt`, and the exact
  generated `/release.json`;
- supplies exact MIME mappings for each public file type;
- leaves Nginx static-file byte ranges enabled and limits requests to one
  range;
- disables directory indexes and rejects unknown paths and dotfiles;
- restricts asset CORS to `https://cs.avasan.org` and does not add CORS to
  release metadata;
- adds conservative cache, content-sniffing, framing, referrer, CSP, and
  cross-origin-resource headers;
- explicitly emits HSTS because location-level response headers do not inherit
  an HSTS header from the surrounding server block in standard Nginx.

Stable course URLs intentionally keep stable filenames, so assets use a
one-hour cache rather than `immutable`. This limits stale content after a
reviewed replacement.

## Prepare a release

Set `VERSION` to the intended release number, commit and push that change, and
create exactly one annotated `vMAJOR.MINOR.PATCH` tag on the same `origin/main`
commit. Lightweight tags and tags not matching `VERSION` are not deployable.
Then use a clean checkout of that exact tag:

```bash
git lfs install
git lfs pull
git lfs checkout
./scripts/verify-lfs-checkout.sh
./scripts/verify-required-assets.sh
```

The second verification checks all local files against
`asset-manifest.sha256`. Never deploy while either command fails.

Resolve the release inputs from the release record and verify them explicitly:

```bash
static_expected_version="1.0.3"
static_expected_revision="<full-lowercase-40-character-commit>"
./scripts/verify-release-source.sh \
  "${static_expected_version}" "${static_expected_revision}"
```

The gate requires a clean checkout, the full HEAD revision, the matching
`VERSION`, and one annotated `v${static_expected_version}` tag. CI, production,
and the external workflow additionally require that revision to equal
`origin/main`; the local staging check can therefore run before the first push.

Install the version-controlled Nginx include, validate Nginx, and reload before
the first release that exposes `/release.json`:

```bash
sudo install -m 0644 deploy/nginx/static.cs.avasan.org-assets.conf \
  /etc/nginx/snippets/static.cs.avasan.org-assets.conf
sudo nginx -t
sudo systemctl reload nginx
```

On the Linux host, generate and stage the commit-specific payload, verify its
exact inventory and checksums, and atomically switch `current` only after every
source and metadata check succeeds:

```bash
./scripts/prepare-release.sh \
  --release-root /var/www/static.cs.avasan.org \
  --expected-version "${static_expected_version}" \
  --expected-revision "${static_expected_revision}"
```

The script generates canonical two-field `release.json` inside the staging
directory. It rechecks HEAD, tag, version, revision, assets, inventory, and JSON
before symlink promotion. Any mismatch leaves `current` unchanged; an existing
commit directory is never mutated.

Run release preparation as a deployment user that can write the release
directory. The Nginx worker needs read and directory-traversal access, but it
should not own or modify releases. A partially copied directory must never
become `current`.

## Verify from outside the home network

Run the repository verifier on a host that resolves and reaches the public
service:

```bash
./scripts/verify-deployment.sh \
  --expected-version "${static_expected_version}" \
  --expected-revision "${static_expected_revision}"
```

It first requires `/release.json` to exactly match the selected tagged source,
then performs HTTPS `HEAD` checks for all 105 manifest paths, validates status,
MIME, size, range, CORS, cache, and security headers, downloads only three
1,024-byte representative ranges, and confirms that `/`, indexes, the binary
manifest, and dotfiles are not public. It does not inspect or download local
LFS objects.

The manual **Post-deploy verification** GitHub Actions workflow checks out the
exact annotated version tag, verifies it against the full expected revision and
`origin/main`, and then runs the public gate from an external runner without
downloading LFS objects. Supply a different HTTPS base URL only when validating
a staging virtual host.

Do not treat a local failure as definitive when NAT hairpin routing is
unreliable. The external workflow result is the release gate.

## Roll back

Point `current` at a previously verified commit directory, validate Nginx,
reload, and rerun the external workflow with that release's exact version and
revision. Keep the failed release available until the discrepancy is
understood; do not mutate an older release in place.
