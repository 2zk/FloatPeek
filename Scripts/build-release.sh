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

sparkle_public_ed_key="${SPARKLE_PUBLIC_ED_KEY:-}"
source_packages_path="${SOURCE_PACKAGES_PATH:-$repository_root/.build/SourcePackages}"

if [[ -z "$sparkle_public_ed_key" ]]; then
  echo "リリースに必要な環境変数が未設定です: SPARKLE_PUBLIC_ED_KEY" >&2
  exit 64
fi

if ! decoded_public_key_length="$(
  printf '%s' "$sparkle_public_ed_key" |
    base64 --decode 2>/dev/null |
    wc -c |
    tr -d ' '
)"; then
  echo "SPARKLE_PUBLIC_ED_KEY は有効なBase64である必要があります。" >&2
  exit 64
fi
if [[ "$decoded_public_key_length" != "32" ]]; then
  echo "SPARKLE_PUBLIC_ED_KEY は32バイトのEdDSA公開鍵である必要があります。" >&2
  exit 64
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/floatpeek-release.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

derived_data_path="$temporary_directory/DerivedData"
xcarchive_path="$temporary_directory/FloatPeek.xcarchive"
staged_app_path="$xcarchive_path/Products/Applications/FloatPeek.app"

mkdir -p "$output_directory"

xcodebuild archive \
  -project "$repository_root/FloatPeek.xcodeproj" \
  -scheme FloatPeek \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$xcarchive_path" \
  -derivedDataPath "$derived_data_path" \
  -clonedSourcePackagesDirPath "$source_packages_path" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  SPARKLE_PUBLIC_ED_KEY="$sparkle_public_ed_key"

if [[ ! -d "$staged_app_path" ]]; then
  echo "アーカイブ済みアプリが見つかりません: $staged_app_path" >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "$staged_app_path"
signature_details="$(codesign -dv --verbose=4 "$staged_app_path" 2>&1)"
if ! grep -Fq "Signature=adhoc" <<<"$signature_details"; then
  echo "配布アプリは ad-hoc 署名である必要があります。" >&2
  exit 65
fi

entitlement_details="$(codesign -d --entitlements - "$staged_app_path" 2>&1)"
if ! grep -Fq "com.apple.security.cs.disable-library-validation" <<<"$entitlement_details" ||
  ! grep -Fq "[Bool] true" <<<"$entitlement_details"; then
  echo "ad-hoc 配布で Sparkle を読み込むための Library Validation 設定がありません。" >&2
  exit 65
fi

actual_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$staged_app_path/Contents/Info.plist")"
if [[ "$actual_version" != "$version" ]]; then
  echo "アプリのバージョンが一致しません: expected=$version actual=$actual_version" >&2
  exit 65
fi

actual_build_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$staged_app_path/Contents/Info.plist")"
if [[ "$actual_build_number" != "$build_number" ]]; then
  echo "アプリのビルド番号が一致しません: expected=$build_number actual=$actual_build_number" >&2
  exit 65
fi

architectures="$(lipo -archs "$staged_app_path/Contents/MacOS/FloatPeek")"
if [[ "$architectures" != "arm64" ]]; then
  echo "配布アプリは arm64 のみである必要があります: $architectures" >&2
  exit 65
fi

sparkle_framework_path="$staged_app_path/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$sparkle_framework_path" ]]; then
  echo "Sparkle.framework が配布アプリに含まれていません。" >&2
  exit 65
fi

actual_public_ed_key="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$staged_app_path/Contents/Info.plist")"
if [[ "$actual_public_ed_key" != "$sparkle_public_ed_key" ]]; then
  echo "アプリに埋め込まれた Sparkle 公開鍵が一致しません。" >&2
  exit 65
fi

ditto -c -k --sequesterRsrc --keepParent "$staged_app_path" "$archive_path"
shasum -a 256 "$archive_path" > "$checksum_path"

echo "配布ファイル: $archive_path"
echo "SHA-256: $(awk '{print $1}' "$checksum_path")"
echo "注意: 配布アプリは ad-hoc 署名であり、Apple の公証を受けていません。"
