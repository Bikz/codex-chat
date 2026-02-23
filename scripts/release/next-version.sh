#!/usr/bin/env bash
set -euo pipefail

PREFIX="${1:-v}"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [prefix]" >&2
  exit 1
fi

latest_tag="$(
  git tag --list "${PREFIX}[0-9]*.[0-9]*.[0-9]*" \
    | sort -V \
    | tail -n 1
)"

if [[ -z "$latest_tag" ]]; then
  echo "${PREFIX}0.0.1"
  exit 0
fi

version_without_prefix="${latest_tag#$PREFIX}"
IFS='.' read -r major minor patch <<<"$version_without_prefix"

if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "error: invalid semver tag detected: $latest_tag" >&2
  exit 1
fi

if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
  echo "error: non-numeric semver tag detected: $latest_tag" >&2
  exit 1
fi

next_patch=$((patch + 1))
echo "${PREFIX}${major}.${minor}.${next_patch}"
