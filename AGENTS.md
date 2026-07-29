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
- Never create fake placeholders for source media that does not exist. Leave
  those paths documented as pending in `PENDING.md` and in the course UI.

## Validation and Delivery

- Run `./scripts/verify-lfs-checkout.sh` and
  `./scripts/verify-required-assets.sh` before committing.
- Regenerate checksums with `./scripts/build-asset-manifest.sh` only after an
  intentional asset change, then inspect the manifest diff.
- Commit and push each coherent, validated change set.
- Use lowercase annotated semantic-version tags for deployable asset snapshots.
  Publish a GitHub release only for a real delivery milestone.
- After deployment, validate every manifest path from outside the home network;
  local NAT hairpin checks can be unreliable.
