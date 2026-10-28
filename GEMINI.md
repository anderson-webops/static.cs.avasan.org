# Workspace Instructions

## Standing Dependency Completion Policy

Read and follow the standing dependency completion policy in `AGENTS.md` in
this directory. It requires complete dependency remediation, clean locked
installations, zero-vulnerability full and production audits, applicable checks
before release, and validated source delivery. Existing maintenance pauses,
exclusions, approvals and production-access boundaries remain in force.
Published releases and verified live deployments are separate outcomes.

Follow `AGENTS.md`. This repository is an intentionally narrow, Git LFS-backed
asset set for Julio's five courses. Preserve root-level filenames, do not add
unrelated upstream material, and run both local asset verification scripts
before delivery. Keep the version-controlled Nginx include and deployment guide
aligned, and use the external post-deploy verifier without fetching LFS objects
when checking the public host.
