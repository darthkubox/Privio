#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/.build/release"
archive_path="$output_dir/Privio.xcarchive"
app_path="$archive_path/Products/Applications/Privio.app"
dmg_path="$output_dir/Privio.dmg"
version=${PRIVIO_VERSION:-0.1.4}
build_number=${PRIVIO_BUILD:-5}

if [[ -z "${TEAM_ID:-}" ]]; then
  print -u2 "Missing TEAM_ID (Apple Developer Team ID)."
  exit 2
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  print -u2 "Missing NOTARY_PROFILE (notarytool keychain profile name)."
  exit 2
fi

cd "$repo_dir"
mkdir -p "$output_dir"

# G2 Sub-CA identity only, by SHA-1 (see Scripts/developer_id.sh).
source "$repo_dir/Scripts/developer_id.sh"
signing_identity=$(developer_id_identity Application "$TEAM_ID") || exit 5

xcodegen generate

xcodebuild \
  -project Privio.xcodeproj \
  -scheme Privio \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  archive \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity"

# Sparkle ships its helper binaries (Autoupdate, Updater.app, XPC services) ad-hoc
# signed, and `xcodebuild archive` does not deep-sign them with our Developer ID.
# Notarization rejects any nested binary lacking a Developer ID signature + secure
# timestamp, so re-sign them inside-out, preserving Sparkle's own entitlements, then
# re-seal the host app with the identity resolved above.

resign() {  # <path>
  codesign --force --options runtime --timestamp \
    --preserve-metadata=entitlements \
    --sign "$signing_identity" "$1"
}

sparkle="$app_path/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  resign "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  resign "$sparkle/Versions/B/XPCServices/Installer.xpc"
  resign "$sparkle/Versions/B/Updater.app"
  resign "$sparkle/Versions/B/Autoupdate"
  resign "$sparkle/Versions/B/Sparkle"
  resign "$sparkle"
fi
# The independently launched recovery tool must also carry a timestamped signature.
resign "$app_path/Contents/MacOS/PrivioWatchdog"
# Re-seal the host app last; nested changes invalidate its outer signature.
resign "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"

staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
cp -R "$app_path" "$staging_dir/Privio.app"
ln -s /Applications "$staging_dir/Applications"

rm -f "$dmg_path"
hdiutil create \
  -volname Privio \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

xcrun notarytool submit "$dmg_path" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

shasum -a 256 "$dmg_path"
print "Release ready: $dmg_path"
