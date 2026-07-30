#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/release-config.sh
source "$script_directory/lib/release-config.sh"

validation_version="99.0.0"
validation_build_number="999999"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/floatpeek-pipeline-validation.XXXXXX")"
tap_name="floatpeek/release-validation-$$"
tap_created=false

cleanup() {
  if [[ "$tap_created" == true ]]; then
    tap_directory="$(brew --repository "$tap_name" 2>/dev/null || true)"
    if [[ -n "$tap_directory" ]]; then
      rm -f "$tap_directory/Casks/floatpeek.rb"
    fi
    brew untap "$tap_name" >/dev/null 2>&1 || true
  fi
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

key_output="$(xcrun swift "$script_directory/generate-test-update-keys.swift")"
sparkle_public_key="$(sed -n 's/^SPARKLE_PUBLIC_ED_KEY=//p' <<<"$key_output")"
sparkle_private_key="$(sed -n 's/^SPARKLE_ED_PRIVATE_KEY=//p' <<<"$key_output")"
if [[ -z "$sparkle_public_key" || -z "$sparkle_private_key" ]]; then
  echo "使い捨てSparkle鍵を生成できませんでした。" >&2
  exit 65
fi

output_directory="$temporary_directory/dist"
BUILD_NUMBER="$validation_build_number" \
  SPARKLE_PUBLIC_ED_KEY="$sparkle_public_key" \
  "$script_directory/build-release.sh" \
    "$validation_version" \
    "$output_directory"

archive_name="$FLOATPEEK_APP_NAME-$validation_version.zip"
archive_path="$output_directory/$archive_name"
release_notes_path="$output_directory/$FLOATPEEK_APP_NAME-$validation_version.md"

printf '# %s %s\n\nRelease pipeline validation.\n' \
  "$FLOATPEEK_APP_NAME" \
  "$validation_version" \
  >"$release_notes_path"

BUILD_NUMBER="$validation_build_number" \
  SPARKLE_ED_PRIVATE_KEY="$sparkle_private_key" \
  "$script_directory/generate-appcast.sh" \
    "$validation_version" \
    "$validation_build_number" \
    "$archive_path" \
    "$release_notes_path"

(
  cd "$output_directory"
  shasum -a 256 -c "$archive_name.sha256"
)

GIT_AUTHOR_NAME="FloatPeek CI" \
  GIT_AUTHOR_EMAIL="github-actions[bot]@users.noreply.github.com" \
  GIT_COMMITTER_NAME="FloatPeek CI" \
  GIT_COMMITTER_EMAIL="github-actions[bot]@users.noreply.github.com" \
  brew tap-new "$tap_name" >/dev/null
tap_created=true
tap_directory="$(brew --repository "$tap_name")"
mkdir -p "$tap_directory/Casks"

archive_sha256="$(awk '{print $1}' "$archive_path.sha256")"
"$script_directory/render-homebrew-cask.sh" \
  "$validation_version" \
  "$archive_sha256" \
  >"$tap_directory/Casks/floatpeek.rb"

brew style --cask "$tap_name/floatpeek"

echo "リリースパイプライン検証: 成功"
