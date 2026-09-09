#!/bin/zsh
set -euo pipefail

# Build a PUBLIC, notarized Privio installer package for the Sparkle update feed.
#
# This is the notarized-.pkg counterpart of build_release.sh (which produces a DMG).
# Sparkle updates Privio via installationType="package", so the update feed needs a
# .pkg signed with Developer ID Installer, notarized + stapled, then signed by Sparkle's
# sign_update (EdDSA). The signing sequence for the app itself mirrors build_release.sh;
# the packaging mirrors build_admin_installer.sh but with a real Developer ID Installer
# signature and Apple notarization instead of the local-only "Privio Local Dev" cert.
#
# Requires: TEAM_ID (Apple Developer Team ID) and NOTARY_PROFILE (notarytool keychain profile).
# Usage:
#   PRIVIO_VERSION=0.1.0 PRIVIO_BUILD=1 TEAM_ID=37VNW38X5U NOTARY_PROFILE=privio-notary \
#     Scripts/build_release_pkg.sh

repo_dir=${0:A:h:h}
output_dir="$repo_dir/.build/release-pkg"
archive_path="$output_dir/Privio.xcarchive"
app_path="$archive_path/Products/Applications/Privio.app"
version=${PRIVIO_VERSION:-0.1.0}
build_number=${PRIVIO_BUILD:-1}
pkg_path="$output_dir/Privio-$version.pkg"
component_path="$output_dir/Privio-component.pkg"
resources_dir="$output_dir/InstallerResources"
distribution_path="$output_dir/Distribution.xml"

# The production feed baked into every Release build. A public package MUST carry this
# exact SUFeedURL; the guardrail below refuses to ship anything else.
production_feed="https://priviolock.com/updates/appcast.xml"

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

xcodegen generate

# Never override PRIVIO_UPDATE_FEED_URL here: the Release config already bakes the
# production feed, and library validation stays ON (Developer ID gives every nested
# framework the same Team ID, so no disable-library-validation exception is needed —
# that entitlement is strictly for the local self-signed path).
rm -rf "$archive_path"
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
  CODE_SIGN_IDENTITY='Developer ID Application'

# Sparkle ships its helper binaries (Autoupdate, Updater.app, XPC services) ad-hoc
# signed, and `xcodebuild archive` does not deep-sign them with our Developer ID.
# Notarization rejects any nested binary lacking a Developer ID signature + secure
# timestamp, so re-sign them inside-out, preserving Sparkle's own entitlements, then
# re-seal the host app. (Identical to build_release.sh.)
signing_identity=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep "$TEAM_ID" \
  | grep -oE '[0-9A-F]{40}' | head -1)
if [[ -z "$signing_identity" ]]; then
  print -u2 "No 'Developer ID Application' identity for team $TEAM_ID in the keychain."
  exit 5
fi

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
# Re-seal the host app last; nested changes invalidate its outer signature.
resign "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

# Guardrail: the app must carry the production feed. A public package that shipped a
# localhost or stale feed would 404 every recipient on "Check for Updates...".
baked_feed=$(/usr/bin/plutil -extract SUFeedURL raw "$app_path/Contents/Info.plist" 2>/dev/null || true)
print "Baked update feed: ${baked_feed:-<none>}"
if [[ "$baked_feed" != "$production_feed" ]]; then
  print -u2 "Feed mismatch: baked '${baked_feed:-<none>}' but expected '$production_feed'."
  print -u2 "Refusing to ship a public package with a non-production feed."
  exit 6
fi

# Resolve the Developer ID Installer identity (installer certs are not under the
# codesigning policy, so query the default identity list).
installer_identity=$(security find-identity -v \
  | grep "Developer ID Installer" | grep "$TEAM_ID" \
  | grep -oE '[0-9A-F]{40}' | head -1)
if [[ -z "$installer_identity" ]]; then
  print -u2 "No 'Developer ID Installer' identity for team $TEAM_ID in the keychain."
  exit 7
fi

rm -f "$pkg_path" "$component_path"

# Build the component with bundle relocation DISABLED, so macOS installs into
# /Applications instead of "relocating" onto a stale registered copy. (From
# build_admin_installer.sh.)
root_dir="$output_dir/root"
component_plist="$output_dir/component.plist"
rm -rf "$root_dir"; mkdir -p "$root_dir"
cp -R "$app_path" "$root_dir/"
pkgbuild --analyze --root "$root_dir" "$component_plist"
/usr/bin/python3 - "$component_plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    items = plistlib.load(f)
for item in items:
    item["BundleIsRelocatable"] = False
with open(path, "wb") as f:
    plistlib.dump(items, f)
PY

# postinstall launches the app after installation (must be executable).
scripts_stage="$output_dir/scripts"
rm -rf "$scripts_stage"; mkdir -p "$scripts_stage"
cp "$repo_dir/Installer/scripts/postinstall" "$scripts_stage/postinstall"
chmod +x "$scripts_stage/postinstall"

pkgbuild \
  --root "$root_dir" \
  --component-plist "$component_plist" \
  --identifier com.privio.Privio.pkg \
  --version "$version" \
  --install-location /Applications \
  --scripts "$scripts_stage" \
  --ownership recommended \
  "$component_path"

# System Installer requires an explicit Accept/Disagree decision. License + welcome
# panes are rendered from Markdown to RTF. Localized lookup picks the current language.
rm -rf "$resources_dir"
mkdir -p "$resources_dir/pl.lproj" "$resources_dir/en.lproj"
md_rtf() {  # <source.md> <out.rtf>
  local tmp_html="${2%.rtf}.html"
  /usr/bin/python3 "$repo_dir/Scripts/md_to_html.py" "$1" > "$tmp_html"
  textutil -convert rtf -output "$2" "$tmp_html"
  rm -f "$tmp_html"
}
md_rtf "$repo_dir/EULA.md"                 "$resources_dir/pl.lproj/License.rtf"
md_rtf "$repo_dir/EULA.en.md"              "$resources_dir/en.lproj/License.rtf"
md_rtf "$repo_dir/Installer/Welcome.pl.md" "$resources_dir/pl.lproj/Welcome.rtf"
md_rtf "$repo_dir/Installer/Welcome.en.md" "$resources_dir/en.lproj/Welcome.rtf"

cp "$repo_dir/Installer/logo-light.png" "$resources_dir/background.png"
cp "$repo_dir/Installer/logo-dark.png"  "$resources_dir/background-dark.png"

sed "s/__PRIVIO_VERSION__/$version/g" "$repo_dir/Installer/Distribution.xml" > "$distribution_path"

# Sign the product archive with Developer ID Installer (public, notarizable).
productbuild \
  --distribution "$distribution_path" \
  --resources "$resources_dir" \
  --package-path "$output_dir" \
  --sign "$installer_identity" \
  --timestamp \
  "$pkg_path"

# Notarize + staple the installer package.
xcrun notarytool submit "$pkg_path" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$pkg_path"
xcrun stapler validate "$pkg_path"

# Authoritative Gatekeeper check for an installer package.
spctl --assess --type install --verbose=2 "$pkg_path"
pkgutil --check-signature "$pkg_path"
shasum -a 256 "$pkg_path"

print "Notarized release package ready: $pkg_path"
print "Next: Scripts/make_appcast.sh $version $build_number <enclosure-url>"
