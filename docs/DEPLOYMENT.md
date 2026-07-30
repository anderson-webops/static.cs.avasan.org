# Static asset deployment

This repository is a curated payload, not a general-purpose document root.
Deploy only the 105 files named by `asset-manifest.sha256` and `robots.txt`.
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

- permits only root-level ZIP, GIF, and MP4 names plus `robots.txt`;
- supplies exact MIME mappings for each public file type;
- leaves Nginx static-file byte ranges enabled and limits requests to one
  range;
- disables directory indexes and rejects unknown paths and dotfiles;
- restricts asset CORS to `https://cs.avasan.org`;
- adds conservative cache, content-sniffing, framing, referrer, CSP, and
  cross-origin-resource headers;
- explicitly emits HSTS because location-level response headers do not inherit
  an HSTS header from the surrounding server block in standard Nginx.

Stable course URLs intentionally keep stable filenames, so assets use a
one-hour cache rather than `immutable`. This limits stale content after a
reviewed replacement.

## Prepare a release

Use a clean checkout of the exact revision intended for deployment:

```bash
git lfs install
git lfs pull
git lfs checkout
./scripts/verify-lfs-checkout.sh
./scripts/verify-required-assets.sh
```

The second verification checks all local files against
`asset-manifest.sha256`. Never deploy while either command fails.

On the Linux host, stage a commit-specific payload and switch the `current`
symlink only after every file has been copied:

```bash
static_repo_root="$(git rev-parse --show-toplevel)"
static_release_id="$(git rev-parse HEAD)"
static_release_root="/var/www/static.cs.avasan.org/releases/${static_release_id}"

if [[ -e "${static_release_root}" ]]; then
  echo "Release directory already exists: ${static_release_root}" >&2
  exit 1
fi

install -d -m 0755 "${static_release_root}"
while read -r _ static_manifest_path; do
  static_asset_name="${static_manifest_path#./}"
  install -m 0644 -- "${static_asset_name}" \
    "${static_release_root}/${static_asset_name}"
done < asset-manifest.sha256
install -m 0644 -- robots.txt "${static_release_root}/robots.txt"

(cd "${static_release_root}" &&
  sha256sum --check "${static_repo_root}/asset-manifest.sha256")

ln -sfnT "${static_release_root}" \
  /var/www/static.cs.avasan.org/current.next
mv -Tf /var/www/static.cs.avasan.org/current.next \
  /var/www/static.cs.avasan.org/current
```

Run those commands as a deployment user that can write the release directory.
The Nginx worker needs read and directory-traversal access, but it should not
own or modify releases. A partially copied directory must never become
`current`.

Install the version-controlled include, validate Nginx, and reload only after
the syntax check succeeds:

```bash
sudo install -m 0644 deploy/nginx/static.cs.avasan.org-assets.conf \
  /etc/nginx/snippets/static.cs.avasan.org-assets.conf
sudo nginx -t
sudo systemctl reload nginx
```

## Verify from outside the home network

Run the repository verifier on a host that resolves and reaches the public
service:

```bash
./scripts/verify-deployment.sh
```

It performs HTTPS `HEAD` checks for all 105 manifest paths, validates status,
MIME, size, range, CORS, cache, and security headers, downloads only three
1,024-byte representative ranges, and confirms that indexes, manifests, and
dotfiles are not public. It does not inspect or download local LFS objects.

The manual **Post-deploy verification** GitHub Actions workflow provides an
external runner and explicitly disables LFS downloads. Supply a different
HTTPS base URL only when validating a staging virtual host.

Do not treat a local failure as definitive when NAT hairpin routing is
unreliable. The external workflow result is the release gate.

## Roll back

Point `current` at a previously verified release, validate Nginx, reload, and
rerun the external verification workflow. Keep the failed release available
until the discrepancy is understood; do not mutate an older release in place.
