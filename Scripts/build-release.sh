#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "使い方: $0 <version> [output-directory]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 64
fi

version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "バージョンは X.Y.Z 形式で指定してください: $version" >&2
  exit 64
fi

build_number="${BUILD_NUMBER:-1}"
if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "BUILD_NUMBER は数字、またはピリオド区切りの数字で指定してください: $build_number" >&2
  exit 64
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
# shellcheck source=Scripts/lib/release-config.sh
source "$script_directory/lib/release-config.sh"
output_directory="${2:-$repository_root/dist}"
if [[ "$output_directory" != /* ]]; then
  output_directory="$repository_root/$output_directory"
fi

archive_name="$FLOATPEEK_APP_NAME-$version.zip"
archive_path="$output_directory/$archive_name"
checksum_path="$archive_path.sha256"
if [[ -e "$archive_path" || -e "$checksum_path" ]]; then
  echo "既存の配布ファイルを上書きしません: $archive_path" >&2
  exit 73
fi

sparkle_public_ed_key="${SPARKLE_PUBLIC_ED_KEY:-}"
source_packages_path="${SOURCE_PACKAGES_PATH:-$repository_root/.build/SourcePackages}"

if [[ -n "$sparkle_public_ed_key" ]]; then
  if ! decoded_public_key_length="$(
    printf '%s' "$sparkle_public_ed_key" |
      base64 --decode 2>/dev/null |
      wc -c |
      tr -d ' '
  )"; then
    echo "SPARKLE_PUBLIC_ED_KEYは有効なBase64である必要があります。" >&2
    exit 64
  fi
  if [[ "$decoded_public_key_length" != "32" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEYは32バイトのEdDSA公開鍵である必要があります。" >&2
    exit 64
  fi
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/floatpeek-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

derived_data_path="$temporary_directory/DerivedData"
xcarchive_path="$temporary_directory/$FLOATPEEK_APP_NAME.xcarchive"
staged_app_path="$xcarchive_path/Products/Applications/$FLOATPEEK_APP_NAME.app"

mkdir -p "$output_directory"

build_settings=(
  "ARCHS=$FLOATPEEK_ARCHITECTURE"
  "ONLY_ACTIVE_ARCH=NO"
  "CODE_SIGN_STYLE=Manual"
  "CODE_SIGN_IDENTITY=-"
  "CODE_SIGNING_ALLOWED=YES"
  "CODE_SIGNING_REQUIRED=YES"
  "AD_HOC_CODE_SIGNING_ALLOWED=YES"
  "MARKETING_VERSION=$version"
  "CURRENT_PROJECT_VERSION=$build_number"
)
if [[ -n "$sparkle_public_ed_key" ]]; then
  build_settings+=("SPARKLE_PUBLIC_ED_KEY=$sparkle_public_ed_key")
fi

xcodebuild archive \
  -project "$repository_root/$FLOATPEEK_APP_NAME.xcodeproj" \
  -scheme "$FLOATPEEK_APP_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$xcarchive_path" \
  -derivedDataPath "$derived_data_path" \
  -clonedSourcePackagesDirPath "$source_packages_path" \
  "${build_settings[@]}"

if [[ ! -d "$staged_app_path" ]]; then
  echo "アーカイブ済みアプリが見つかりません: $staged_app_path" >&2
  exit 66
fi

"$script_directory/prepare-release-app.sh" \
  "$staged_app_path" \
  "$repository_root/FloatPeek/FloatPeek.entitlements"

"$script_directory/validate-app-bundle.sh" \
  "$staged_app_path" \
  "$version" \
  "$build_number" \
  "$sparkle_public_ed_key"

ditto -c -k --sequesterRsrc --keepParent "$staged_app_path" "$archive_path"
archive_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha256" "$archive_name" > "$checksum_path"

echo "配布ファイル: $archive_path"
echo "SHA-256: $archive_sha256"
echo "注意: 配布アプリは ad-hoc 署名であり、Apple の公証を受けていません。"
