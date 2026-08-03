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
installer_name="$FLOATPEEK_APP_NAME-$version.dmg"
installer_path="$output_directory/$installer_name"
checksum_path="$installer_path.sha256"

if [[ ! -f "$archive_path" ]]; then
  echo "配布ZIPが見つかりません: $archive_path" >&2
  exit 66
fi

if [[ -e "$installer_path" || -e "$checksum_path" ]]; then
  echo "既存のインストーラーを上書きしません: $installer_path" >&2
  exit 73
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/floatpeek-installer.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

staging_directory="$temporary_directory/staging"
temporary_installer_path="$temporary_directory/$installer_name"
mkdir -p "$staging_directory"

ditto -x -k "$archive_path" "$staging_directory"

app_path="$staging_directory/$FLOATPEEK_APP_NAME.app"
if [[ ! -d "$app_path" ]]; then
  echo "配布ZIPにアプリが含まれていません: $app_path" >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
ln -s /Applications "$staging_directory/Applications"

hdiutil create \
  -quiet \
  -volname "$FLOATPEEK_APP_NAME $version" \
  -srcfolder "$staging_directory" \
  -format UDZO \
  "$temporary_installer_path"
hdiutil verify "$temporary_installer_path"

mv "$temporary_installer_path" "$installer_path"
installer_sha256="$(shasum -a 256 "$installer_path" | awk '{print $1}')"
printf '%s  %s\n' "$installer_sha256" "$installer_name" >"$checksum_path"

echo "手動インストーラー: $installer_path"
echo "SHA-256: $installer_sha256"
echo "注意: 収録アプリは ad-hoc 署名であり、Apple の公証を受けていません。"
