#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "使い方: $0 <version> <sha256>" >&2
  exit 64
fi

version="$1"
sha256="$2"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "バージョンは X.Y.Z 形式で指定してください: $version" >&2
  exit 64
fi

if [[ ! "$sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "SHA-256 は 64 桁の16進数で指定してください。" >&2
  exit 64
fi
normalized_sha256="$(printf '%s' "$sha256" | tr '[:upper:]' '[:lower:]')"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_path="$script_directory/../Homebrew/floatpeek.rb.template"

sed \
  -e "s/@VERSION@/$version/g" \
  -e "s/@SHA256@/$normalized_sha256/g" \
  "$template_path"
