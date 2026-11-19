#!/usr/bin/env bash
#
# Builds the release archive that spot uploads to the server.
#
#   build-release.sh <version> [output.tar.gz]
set -euo pipefail

version="${1:?usage: build-release.sh <version> [output.tar.gz]}"
example_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${2:-$example_dir/build/hello-$version.tar.gz}"

# Keep macOS xattrs out of the archive: GNU tar on the server warns about them.
export COPYFILE_DISABLE=1

mkdir -p "$(dirname "$out")"

stage="$(mktemp -d "${TMPDIR:-/tmp}/hello-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

cp -R "$example_dir/app/." "$stage/"
printf '%s\n' "$version" > "$stage/REVISION"

# The archive preserves modes. Make sure nginx can read the release even when
# the files were checked out with a restrictive umask.
chmod -R a+rX "$stage"

tar_opts=(-czf "$out" -C "$stage" .)
if tar --version 2>/dev/null | grep -q 'bsdtar'; then
  # Drop macOS xattrs so GNU tar on the server does not warn about them.
  tar_opts=(--no-xattrs "${tar_opts[@]}")
fi
tar "${tar_opts[@]}"
printf '%s\n' "$out"
