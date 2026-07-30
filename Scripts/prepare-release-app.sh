#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "使い方: $0 <app-path> <entitlements-path>" >&2
  exit 64
fi

app_path="$1"
entitlements_path="$2"

if [[ ! -d "$app_path" ]]; then
  echo "アプリが見つかりません: $app_path" >&2
  exit 66
fi

if [[ ! -f "$entitlements_path" ]]; then
  echo "entitlementsが見つかりません: $entitlements_path" >&2
  exit 66
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/release-config.sh
source "$script_directory/lib/release-config.sh"

while IFS= read -r -d '' file_path; do
  if ! architectures="$(lipo -archs "$file_path" 2>/dev/null)"; then
    continue
  fi

  if [[ " $architectures " != *" $FLOATPEEK_ARCHITECTURE "* ]]; then
    echo "arm64を含まないMach-Oファイルです: $file_path ($architectures)" >&2
    exit 65
  fi

  if [[ "$architectures" == "$FLOATPEEK_ARCHITECTURE" ]]; then
    continue
  fi

  file_mode="$(stat -f '%Lp' "$file_path")"
  thinned_path="$file_path.arm64"
  lipo "$file_path" -thin "$FLOATPEEK_ARCHITECTURE" -output "$thinned_path"
  chmod "$file_mode" "$thinned_path"
  mv "$thinned_path" "$file_path"
done < <(find "$app_path/Contents" -type f -print0)

sparkle_framework_path="$app_path/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$sparkle_framework_path" ]]; then
  echo "Sparkle.frameworkが見つかりません: $sparkle_framework_path" >&2
  exit 66
fi

sparkle_version_path="$(cd "$sparkle_framework_path/Versions/Current" && pwd -P)"
sparkle_signing_targets=(
  "$sparkle_version_path/Autoupdate"
  "$sparkle_version_path/XPCServices/Downloader.xpc"
  "$sparkle_version_path/XPCServices/Installer.xpc"
  "$sparkle_version_path/Updater.app"
  "$sparkle_version_path"
)

for signing_target in "${sparkle_signing_targets[@]}"; do
  if [[ ! -e "$signing_target" ]]; then
    echo "Sparkle署名対象が見つかりません: $signing_target" >&2
    exit 66
  fi

  codesign \
    --force \
    --sign - \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags \
    "$signing_target"
done

codesign \
  --force \
  --sign - \
  --timestamp=none \
  --options runtime \
  --entitlements "$entitlements_path" \
  "$app_path"
