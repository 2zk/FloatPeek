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
output_directory="${2:-$repository_root/dist}"
if [[ "$output_directory" != /* ]]; then
  output_directory="$repository_root/$output_directory"
fi

archive_name="FloatPeek-$version.zip"
archive_path="$output_directory/$archive_name"
checksum_path="$archive_path.sha256"
if [[ -e "$archive_path" || -e "$checksum_path" ]]; then
  echo "既存の配布ファイルを上書きしません: $archive_path" >&2
  exit 73
fi

signing_identity="${SIGNING_IDENTITY:--}"
apple_id="${APPLE_ID:-}"
apple_team_id="${APPLE_TEAM_ID:-}"
apple_app_specific_password="${APPLE_APP_SPECIFIC_PASSWORD:-}"

notarization_value_count=0
[[ -n "$apple_id" ]] && notarization_value_count=$((notarization_value_count + 1))
[[ -n "$apple_team_id" ]] && notarization_value_count=$((notarization_value_count + 1))
[[ -n "$apple_app_specific_password" ]] && notarization_value_count=$((notarization_value_count + 1))

if [[ $notarization_value_count -ne 0 && $notarization_value_count -ne 3 ]]; then
  echo "公証には APPLE_ID、APPLE_TEAM_ID、APPLE_APP_SPECIFIC_PASSWORD のすべてが必要です。" >&2
  exit 64
fi

if [[ $notarization_value_count -eq 3 && "$signing_identity" == "-" ]]; then
  echo "公証する場合は Developer ID Application の SIGNING_IDENTITY が必要です。" >&2
  exit 64
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/floatpeek-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

derived_data_path="$temporary_directory/DerivedData"
app_path="$derived_data_path/Build/Products/Release/FloatPeek.app"

mkdir -p "$output_directory"

xcodebuild build \
  -project "$repository_root/FloatPeek.xcodeproj" \
  -scheme FloatPeek \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number"

if [[ ! -d "$app_path" ]]; then
  echo "ビルド済みアプリが見つかりません: $app_path" >&2
  exit 66
fi

staged_app_path="$temporary_directory/FloatPeek.app"
ditto "$app_path" "$staged_app_path"

codesign_arguments=(
  --force
  --deep
  --options runtime
  --sign "$signing_identity"
)
if [[ "$signing_identity" != "-" ]]; then
  codesign_arguments+=(--timestamp)
fi
codesign "${codesign_arguments[@]}" "$staged_app_path"
codesign --verify --deep --strict --verbose=2 "$staged_app_path"

actual_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$staged_app_path/Contents/Info.plist")"
if [[ "$actual_version" != "$version" ]]; then
  echo "アプリのバージョンが一致しません: expected=$version actual=$actual_version" >&2
  exit 65
fi

architectures="$(lipo -archs "$staged_app_path/Contents/MacOS/FloatPeek")"
for required_architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $required_architecture "* ]]; then
    echo "必要なアーキテクチャが含まれていません: $required_architecture ($architectures)" >&2
    exit 65
  fi
done

if [[ $notarization_value_count -eq 3 ]]; then
  notarization_archive="$temporary_directory/notarization.zip"
  ditto -c -k --sequesterRsrc --keepParent "$staged_app_path" "$notarization_archive"
  xcrun notarytool submit "$notarization_archive" \
    --apple-id "$apple_id" \
    --team-id "$apple_team_id" \
    --password "$apple_app_specific_password" \
    --wait
  xcrun stapler staple "$staged_app_path"
  xcrun stapler validate "$staged_app_path"
fi

ditto -c -k --sequesterRsrc --keepParent "$staged_app_path" "$archive_path"
shasum -a 256 "$archive_path" > "$checksum_path"

echo "配布ファイル: $archive_path"
echo "SHA-256: $(awk '{print $1}' "$checksum_path")"
