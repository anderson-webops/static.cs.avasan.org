# Repository Guidelines

## Standing Dependency Completion Policy

Treat dependency remediation as part of completing authorized work on this
site, not as an optional follow-up. Proactively resolve vulnerabilities,
compatibility problems, broken installations and lockfile issues. Cover direct
and transitive dependencies, production and development dependencies,
workspaces and root-level tools. Do not dismiss findings because they are
pre-existing or development-only.

Before creating a release tag or publishing a release, require a clean locked
installation for every applicable dependency graph, zero known dependency
vulnerabilities in both full and production audits, and all applicable project
checks. An unavailable or incomplete audit is not a clean result. Use supported
upgrades, replacements or maintainable patches that preserve functionality.
Do not silence findings, weaken checks or force incompatible versions merely
to obtain a passing result.

Intermediate commits may capture coherent progress. Commit and push validated
work through this site's authorized delivery process, and complete meaningful
releases rather than stopping after reporting fixable dependency blockers.
Documentation-only housekeeping does not require an application release.

Preserve unrelated work, coordinate with other active chats, and retain existing
security, approval and production-access boundaries. Existing maintenance pauses
and repository exclusions remain in force; this policy does not expand access
or authorize otherwise excluded work. If a genuine blocker prevents completion,
preserve progress and report the exact blocker and remaining work. Distinguish
a published release from verified live deployment.

Treat this as a standing instruction for this site.

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
