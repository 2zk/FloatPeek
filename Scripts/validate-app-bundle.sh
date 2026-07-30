#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "使い方: $0 <app-path> <version> <build-number> [expected-public-key]" >&2
  exit 64
fi

app_path="$1"
version="$2"
build_number="$3"
expected_public_key="${4:-}"

if [[ ! -d "$app_path" ]]; then
  echo "アプリが見つかりません: $app_path" >&2
  exit 66
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/release-config.sh
source "$script_directory/lib/release-config.sh"

info_plist_path="$app_path/Contents/Info.plist"
main_executable_path="$app_path/Contents/MacOS/$FLOATPEEK_APP_NAME"
sparkle_framework_path="$app_path/Contents/Frameworks/Sparkle.framework"

codesign --verify --deep --strict --verbose=2 "$app_path"

signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
if ! grep -Fq "Signature=adhoc" <<<"$signature_details"; then
  echo "配布アプリはad-hoc署名である必要があります。" >&2
  exit 65
fi

entitlement_details="$(codesign -d --entitlements - "$app_path" 2>&1)"
if ! grep -Fq "com.apple.security.cs.disable-library-validation" <<<"$entitlement_details" ||
  ! grep -Fq "[Bool] true" <<<"$entitlement_details"; then
  echo "ad-hoc配布でSparkleを読み込むためのLibrary Validation設定がありません。" >&2
  exit 65
fi

actual_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist_path")"
if [[ "$actual_version" != "$version" ]]; then
  echo "アプリのバージョンが一致しません: expected=$version actual=$actual_version" >&2
  exit 65
fi

actual_build_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist_path")"
if [[ "$actual_build_number" != "$build_number" ]]; then
  echo "アプリのビルド番号が一致しません: expected=$build_number actual=$actual_build_number" >&2
  exit 65
fi

actual_minimum_macos="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$info_plist_path")"
if [[ "$actual_minimum_macos" != "$FLOATPEEK_MINIMUM_MACOS_VERSION" ]]; then
  echo "最低macOSバージョンが一致しません: expected=$FLOATPEEK_MINIMUM_MACOS_VERSION actual=$actual_minimum_macos" >&2
  exit 65
fi

if [[ ! -x "$main_executable_path" ]]; then
  echo "メイン実行ファイルが見つかりません: $main_executable_path" >&2
  exit 66
fi

if [[ ! -d "$sparkle_framework_path" ]]; then
  echo "Sparkle.frameworkが配布アプリに含まれていません。" >&2
  exit 65
fi

found_macho=false
while IFS= read -r -d '' file_path; do
  if ! architectures="$(lipo -archs "$file_path" 2>/dev/null)"; then
    continue
  fi

  found_macho=true
  if [[ "$architectures" != "$FLOATPEEK_ARCHITECTURE" ]]; then
    echo "配布アプリにarm64以外を含むMach-Oファイルがあります: $file_path ($architectures)" >&2
    exit 65
  fi
done < <(find "$app_path/Contents" -type f -print0)

if [[ "$found_macho" != true ]]; then
  echo "配布アプリにMach-Oファイルがありません。" >&2
  exit 65
fi

actual_public_key="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$info_plist_path")"
if ! decoded_public_key_length="$(
  printf '%s' "$actual_public_key" |
    base64 --decode 2>/dev/null |
    wc -c |
    tr -d ' '
)"; then
  echo "アプリのSUPublicEDKeyが有効なBase64ではありません。" >&2
  exit 65
fi

if [[ "$decoded_public_key_length" != "32" ]]; then
  echo "アプリのSUPublicEDKeyは32バイトのEdDSA公開鍵ではありません。" >&2
  exit 65
fi

if [[ -n "$expected_public_key" && "$actual_public_key" != "$expected_public_key" ]]; then
  echo "アプリに埋め込まれたSparkle公開鍵が一致しません。" >&2
  exit 65
fi

echo "アプリバンドル検証: $app_path"
