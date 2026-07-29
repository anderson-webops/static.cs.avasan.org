#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "${repo_root}" ]]; then
  echo "Run this script from inside the repository." >&2
  exit 1
fi

cd "${repo_root}"

if ! git lfs version >/dev/null 2>&1; then
  echo "Git LFS is not installed. Install it before verifying the checkout." >&2
  exit 1
fi

tracked_count=0
missing_files=()
pointer_files=()

while IFS= read -r path; do
  [[ -n "${path}" ]] || continue
  tracked_count=$((tracked_count + 1))

  if [[ ! -e "${path}" ]]; then
    missing_files+=("${path}")
    continue
  fi

  if git lfs pointer --check --file="${path}" >/dev/null 2>&1; then
    pointer_files+=("${path}")
  fi
done < <(git lfs ls-files -n)

if [[ "${tracked_count}" -eq 0 ]]; then
  echo "No Git LFS-tracked files found." >&2
  exit 1
fi

if [[ "${#missing_files[@]}" -gt 0 || "${#pointer_files[@]}" -gt 0 ]]; then
  echo "Git LFS checkout is incomplete." >&2

  if [[ "${#missing_files[@]}" -gt 0 ]]; then
    echo "Missing tracked files:" >&2
    for path in "${missing_files[@]}"; do
      printf '  %s\n' "${path}" >&2
    done
  fi

  if [[ "${#pointer_files[@]}" -gt 0 ]]; then
    echo "Pointer files still present in the working tree:" >&2
    for path in "${pointer_files[@]}"; do
      printf '  %s\n' "${path}" >&2
    done
  fi

  echo "Run: git lfs install && git lfs pull && git lfs checkout" >&2
  exit 1
fi

echo "Git LFS checkout looks complete (${tracked_count} tracked files verified)."
