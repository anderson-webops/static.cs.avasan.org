# Repository Guidelines

## Purpose

This is the curated static-media repository for `cs.avasan.org`. Keep it limited
to files used by Julio's Scratch, Python 1–2, and PyGames courses. Do not import
unrelated classes, datasets, student information, or account data from the
upstream asset repository.

## Asset Contract

- Preserve published filenames and keep lesson media at the repository root.
- Track ZIP, GIF, and MP4 files with Git LFS.
- Treat `asset-manifest.sha256` as the reviewed inventory of deployable binary
  assets.
- Keep `VERSION` aligned with the one exact annotated release tag. Generate
  `release.json` only inside the commit-specific release directory; never add
  it to the binary manifest or commit it to the repository.
- Never create fake placeholders for source media that does not exist. Leave
  those paths documented as pending in `PENDING.md` and in the course UI.

## Validation and Delivery

- Run `./scripts/verify-lfs-checkout.sh` and
  `./scripts/verify-required-assets.sh` before committing.
- Regenerate checksums with `./scripts/build-asset-manifest.sh` only after an
  intentional asset change, then inspect the manifest diff.
- Keep the Nginx include and `docs/DEPLOYMENT.md` aligned. The public host must
  expose only root-level manifest assets, `robots.txt`, and the generated exact
  `release.json`, with exact MIME types, byte ranges, restricted CORS, and no
  directory or dotfile access. The host root remains a `404`.
- Commit and push each coherent, validated change set.
- Use lowercase annotated semantic-version tags for deployable asset snapshots.
  Publish a GitHub release only for a real delivery milestone.
- After deployment, validate every manifest path from outside the home network;
  local NAT hairpin checks can be unreliable. Use
  `./scripts/verify-deployment.sh` or the manual external-runner workflow.
