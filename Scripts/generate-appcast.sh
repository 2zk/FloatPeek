#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "使い方: $0 <version> <build-number> <archive> [release-notes]" >&2
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 64
fi

version="$1"
build_number="$2"
archive_path="$3"
release_notes_path="${4:-}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "バージョンは X.Y.Z 形式で指定してください: $version" >&2
  exit 64
fi

if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "ビルド番号は数字、またはピリオド区切りの数字で指定してください: $build_number" >&2
  exit 64
fi

if [[ ! -f "$archive_path" ]]; then
  echo "配布アーカイブが見つかりません: $archive_path" >&2
  exit 66
fi

if [[ -n "$release_notes_path" && ! -f "$release_notes_path" ]]; then
  echo "リリースノートが見つかりません: $release_notes_path" >&2
  exit 66
fi

if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_ED_PRIVATE_KEY が未設定です。" >&2
  exit 64
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
source_packages_path="${SOURCE_PACKAGES_PATH:-$repository_root/.build/SourcePackages}"
generate_appcast_path="$source_packages_path/artifacts/sparkle/Sparkle/bin/generate_appcast"
output_directory="$(cd "$(dirname "$archive_path")" && pwd)"
output_path="$output_directory/appcast.xml"

if [[ ! -x "$generate_appcast_path" ]]; then
  echo "Sparkle の generate_appcast が見つかりません: $generate_appcast_path" >&2
  exit 66
fi

if [[ -e "$output_path" ]]; then
  echo "既存の appcast を上書きしません: $output_path" >&2
  exit 73
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/floatpeek-appcast.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

archive_name="FloatPeek-$version.zip"
archive_copy_path="$temporary_directory/$archive_name"
release_url_prefix="https://github.com/2zk/FloatPeek/releases/download/v$version/"

ditto "$archive_path" "$archive_copy_path"
if [[ -n "$release_notes_path" ]]; then
  ditto "$release_notes_path" "$temporary_directory/FloatPeek-$version.md"
fi

printf '%s' "$SPARKLE_ED_PRIVATE_KEY" |
  "$generate_appcast_path" \
    --ed-key-file - \
    --download-url-prefix "$release_url_prefix" \
    --release-notes-url-prefix "$release_url_prefix" \
    --link "https://github.com/2zk/FloatPeek/releases/tag/v$version" \
    --maximum-deltas 0 \
    -o "$output_path" \
    "$temporary_directory"

if [[ -n "$release_notes_path" ]]; then
  ditto "$temporary_directory/FloatPeek-$version.md" "$release_notes_path"
  if ! grep -Fq "sparkle-signatures:" "$release_notes_path"; then
    echo "リリースノートにEdDSA署名がありません。" >&2
    exit 65
  fi
fi

xmllint --noout "$output_path"

archive_size="$(stat -f '%z' "$archive_path")"
required_appcast_values=(
  "<sparkle:version>$build_number</sparkle:version>"
  "<sparkle:shortVersionString>$version</sparkle:shortVersionString>"
  "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
  "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"
  "https://github.com/2zk/FloatPeek/releases/download/v$version/FloatPeek-$version.zip"
  "length=\"$archive_size\""
  "sparkle:edSignature="
  "sparkle-signatures:"
)
for required_value in "${required_appcast_values[@]}"; do
  if ! grep -Fq "$required_value" "$output_path"; then
    echo "appcast に必要な値がありません: $required_value" >&2
    exit 65
  fi
done

echo "更新フィード: $output_path"
