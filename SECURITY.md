# Security

## Reviewed CodeQL exception

Reviewed on 2026-08-01. This asset-only repository contains no application
source in a CodeQL-supported language. GitHub's language inventory reports only
Shell; its default-setup assessment also sees the GitHub Actions workflow
definitions, but no served application code. CodeQL is therefore intentionally
not configured here. Revisit this exception before adding any application
source or another supported language.

## Active safeguards

- GitHub secret scanning and secret-scanning push protection are enabled for
  this public repository.
- Workflows use read-only default permissions and pin third-party Actions to
  full commit revisions.
- CI validates every shell script's syntax and the release-provenance contract.
- All 105 deployable binary assets must be present through Git LFS, match the
  reviewed SHA-256 manifest, and reproduce that manifest exactly.
- Deployment scripts accept only the tagged, clean `origin/main` revision and
  the Nginx allowlist exposes only reviewed assets, `robots.txt`, and exact
  release metadata.

Do not commit credentials or student information. Report a suspected exposure
privately to the repository owners rather than in a public issue.
