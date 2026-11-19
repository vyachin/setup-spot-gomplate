#!/usr/bin/env bash
#
# Renders every *.tmpl file in examples/hello/spot next to its source.
# Requires gomplate on PATH and the environment variables used in the templates.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../spot"
gomplate --input-dir . --include '*.tmpl' --output-map '{{ .in | strings.TrimSuffix ".tmpl" }}'
