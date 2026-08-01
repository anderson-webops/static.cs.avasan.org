# static.cs.avasan.org

Curated static assets for [cs.avasan.org](https://cs.avasan.org), Julio's
grade-school computer science course site.

## Included material

- 77 Python Level 2 demonstration files
- 27 PyGames demonstration videos
- `assets.zip`, the image, music, and sound pack used by the browser Python IDE

The 105 binary assets keep their original root-level filenames because the
course content links to those exact paths.

`/release.json` is generated only while preparing a tagged atomic release. It
contains the release's semantic version and full source commit, is not a course
asset, and is deliberately absent from `asset-manifest.sha256` and Git.

## Deliberately excluded

This repository does not mirror the full source library. It excludes unrelated
courses, datasets, contact information, and administrative material. Media
named by the course catalog but absent from the source remains documented in
[`PENDING.md`](./PENDING.md); no fake placeholder files are substituted.

## Provenance

The initial asset snapshot was curated from
[`anderson-webops/static.classes.jacobdanderson.net`](https://github.com/anderson-webops/static.classes.jacobdanderson.net)
at commit `87e8058b1bf24ef0c0bd7e513a6504d8b7a46422`.

This is an independent downstream repository rather than a GitHub fork because
the source repository already belongs to the same GitHub organization. The
`upstream` Git remote records the source relationship.

## Clone and verify

```bash
git lfs install
git lfs pull
git lfs checkout
./scripts/verify-lfs-checkout.sh
./scripts/verify-required-assets.sh
```

`asset-manifest.sha256` is the reviewed binary inventory and checksum record.
Run `./scripts/build-asset-manifest.sh` only after an intentional asset update,
then inspect the manifest diff before committing.

`VERSION` is the source release version. A deployable checkout must be clean and
named by the one exact annotated `vMAJOR.MINOR.PATCH` tag matching that file.
Release preparation refuses lightweight tags, shortened or uppercase revisions,
mismatched versions, and untracked source files. CI and the external gate also
require that release revision to equal `origin/main`.

## Hosting contract

Deploy the verified, tagged repository checkout as the document root for
`static.cs.avasan.org`. Do not add a path prefix: course URLs use
`https://static.cs.avasan.org/<filename>`. Keep byte-range requests enabled for
MP4 and ZIP downloads, serve `robots.txt` from the root, serve the generated
identity at `/release.json`, and keep `/` unavailable with `404`.

The version-controlled
[`deploy/nginx/static.cs.avasan.org-assets.conf`](./deploy/nginx/static.cs.avasan.org-assets.conf)
is designed to be included by the existing HTTPS Nginx virtual host. Follow
[`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md) for atomic release preparation,
Nginx validation, rollback, and the external post-deploy gate.

After deployment, verify the exact release identity, all 105 public asset paths,
and representative ZIP, GIF, and MP4 byte ranges from outside the home network:

```bash
./scripts/verify-deployment.sh \
  --expected-version 1.0.3 \
  --expected-revision <full-lowercase-40-character-commit>
```

The manual **Post-deploy verification** GitHub Actions workflow performs the
same check from an external runner without downloading Git LFS objects.

There is no application build or package manager in this repository.
