#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "使い方: $0 <version> <build-number> <archive> <appcast> [release-notes]" >&2
  exit 64
fi

version="$1"
build_number="$2"
archive_path="$3"
appcast_path="$4"
release_notes_path="${5:-}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "バージョンはX.Y.Z形式で指定してください: $version" >&2
  exit 64
fi

if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "ビルド番号は数字、またはピリオド区切りの数字で指定してください: $build_number" >&2
  exit 64
fi

for required_file in "$archive_path" "$appcast_path"; do
  if [[ ! -f "$required_file" ]]; then
    echo "検証対象が見つかりません: $required_file" >&2
    exit 66
  fi
done

if [[ -n "$release_notes_path" && ! -f "$release_notes_path" ]]; then
  echo "リリースノートが見つかりません: $release_notes_path" >&2
  exit 66
fi

if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  echo "暗号学的検証に必要なSPARKLE_ED_PRIVATE_KEYが未設定です。" >&2
  exit 64
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
# shellcheck source=Scripts/lib/release-config.sh
source "$script_directory/lib/release-config.sh"

source_packages_path="${SOURCE_PACKAGES_PATH:-$repository_root/.build/SourcePackages}"
sign_update_path="$source_packages_path/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$sign_update_path" ]]; then
  echo "Sparkleのsign_updateが見つかりません: $sign_update_path" >&2
  exit 66
fi

xmllint --noout "$appcast_path"

item_xpath="//*[local-name()='item' and *[local-name()='version' and normalize-space(text())='$build_number'] and *[local-name()='shortVersionString' and normalize-space(text())='$version']]"
item_count="$(xmllint --xpath "count($item_xpath)" "$appcast_path")"
if [[ "$item_count" != "1" ]]; then
  echo "対象バージョンのappcast itemが一意ではありません: count=$item_count" >&2
  exit 65
fi

item_xpath="($item_xpath)[1]"
xpath_string() {
  xmllint --xpath "string($1)" "$appcast_path"
}

actual_minimum_macos="$(xpath_string "$item_xpath/*[local-name()='minimumSystemVersion']")"
if [[ "$actual_minimum_macos" != "$FLOATPEEK_MINIMUM_MACOS_VERSION" ]]; then
  echo "appcastの最低macOSバージョンが一致しません: expected=$FLOATPEEK_MINIMUM_MACOS_VERSION actual=$actual_minimum_macos" >&2
  exit 65
fi

actual_architecture="$(xpath_string "$item_xpath/*[local-name()='hardwareRequirements']")"
if [[ "$actual_architecture" != "$FLOATPEEK_ARCHITECTURE" ]]; then
  echo "appcastのアーキテクチャが一致しません: expected=$FLOATPEEK_ARCHITECTURE actual=$actual_architecture" >&2
  exit 65
fi

enclosure_xpath="$item_xpath/*[local-name()='enclosure']"
enclosure_count="$(xmllint --xpath "count($enclosure_xpath)" "$appcast_path")"
if [[ "$enclosure_count" != "1" ]]; then
  echo "appcast enclosureが一意ではありません: count=$enclosure_count" >&2
  exit 65
fi

expected_archive_url="https://github.com/$FLOATPEEK_REPOSITORY/releases/download/v$version/$FLOATPEEK_APP_NAME-$version.zip"
actual_archive_url="$(xpath_string "$enclosure_xpath/@url")"
if [[ "$actual_archive_url" != "$expected_archive_url" ]]; then
  echo "appcastのアーカイブURLが一致しません: $actual_archive_url" >&2
  exit 65
fi

expected_archive_size="$(stat -f '%z' "$archive_path")"
actual_archive_size="$(xpath_string "$enclosure_xpath/@length")"
if [[ "$actual_archive_size" != "$expected_archive_size" ]]; then
  echo "appcastのアーカイブサイズが一致しません: expected=$expected_archive_size actual=$actual_archive_size" >&2
  exit 65
fi

archive_signature="$(xpath_string "$enclosure_xpath/@*[local-name()='edSignature']")"
if [[ -z "$archive_signature" ]]; then
  echo "appcastのアーカイブにEdDSA署名がありません。" >&2
  exit 65
fi

if ! grep -Fq "<!-- sparkle-signatures:" "$appcast_path"; then
  echo "appcast自体のEdDSA署名ブロックがありません。" >&2
  exit 65
fi

printf '%s' "$SPARKLE_ED_PRIVATE_KEY" |
  "$sign_update_path" --verify --ed-key-file - "$appcast_path"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" |
  "$sign_update_path" --verify --ed-key-file - "$archive_path" "$archive_signature"

if [[ -n "$release_notes_path" ]]; then
  if ! grep -Fq "<!-- sparkle-sign-warning:" "$release_notes_path"; then
    echo "リリースノートに署名済みファイルの警告がありません。" >&2
    exit 65
  fi

  release_notes_xpath="$item_xpath/*[local-name()='releaseNotesLink']"
  release_notes_count="$(xmllint --xpath "count($release_notes_xpath)" "$appcast_path")"
  if [[ "$release_notes_count" != "1" ]]; then
    echo "appcast releaseNotesLinkが一意ではありません: count=$release_notes_count" >&2
    exit 65
  fi

  expected_release_notes_url="https://github.com/$FLOATPEEK_REPOSITORY/releases/download/v$version/$FLOATPEEK_APP_NAME-$version.md"
  actual_release_notes_url="$(xpath_string "$release_notes_xpath")"
  if [[ "$actual_release_notes_url" != "$expected_release_notes_url" ]]; then
    echo "appcastのリリースノートURLが一致しません: $actual_release_notes_url" >&2
    exit 65
  fi

  expected_release_notes_size="$(stat -f '%z' "$release_notes_path")"
  actual_release_notes_size="$(xpath_string "$release_notes_xpath/@*[local-name()='length']")"
  if [[ "$actual_release_notes_size" != "$expected_release_notes_size" ]]; then
    echo "appcastのリリースノートサイズが一致しません: expected=$expected_release_notes_size actual=$actual_release_notes_size" >&2
    exit 65
  fi

  release_notes_signature="$(xpath_string "$release_notes_xpath/@*[local-name()='edSignature']")"
  if [[ -z "$release_notes_signature" ]]; then
    echo "appcastのリリースノートにEdDSA署名がありません。" >&2
    exit 65
  fi

  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" |
    "$sign_update_path" \
      --verify \
      --ed-key-file - \
      "$release_notes_path" \
      "$release_notes_signature"
fi

echo "appcast検証: $appcast_path"
