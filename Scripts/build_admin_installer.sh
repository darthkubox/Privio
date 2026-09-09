#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/.build/admin-installer"
derived_data="$output_dir/DerivedData"
app_path="$derived_data/Build/Products/Release/Privio.app"
pkg_path="$output_dir/Privio-admin-install.pkg"
component_path="$output_dir/Privio-component.pkg"
resources_dir="$output_dir/InstallerResources"
distribution_path="$output_dir/Distribution.xml"
version=${PRIVIO_VERSION:-0.1.0}
build_number=${PRIVIO_BUILD:-1}
code_sign_identity=${PRIVIO_CODE_SIGN_IDENTITY:-Privio Local Dev}
local_entitlements="$repo_dir/Installer/PrivioLocal.entitlements"

cd "$repo_dir"
mkdir -p "$output_dir"

# Bluetooth TCC and the Vault Keychain ACL identify the application by its code-signing
# requirement. Ad-hoc signing changes that identity between builds, invalidating permissions.
# Refuse to produce a local installer unless the stable local identity is available.
if ! security find-identity -v -p codesigning | grep -Fq "\"$code_sign_identity\""; then
  print -u2 "Missing valid code-signing identity: $code_sign_identity"
  print -u2 "Create/trust it in Keychain Access or set PRIVIO_CODE_SIGN_IDENTITY."
  exit 3
fi

xcodegen generate

# DerivedData records absolute paths to package artifacts. Reusing it after the
# repository was moved can silently embed Sparkle from an obsolete checkout.
rm -rf "$derived_data"

# Optional feed override for LOCAL testing only: when PRIVIO_UPDATE_FEED_URL is set,
# it is baked into the built app's Info.plist (SUFeedURL). This lets a package-installed
# copy check a localhost appcast instead of the production GitHub feed. Never set this
# for a real distributable build.
feed_override=()
if [[ -n "${PRIVIO_UPDATE_FEED_URL:-}" ]]; then
  feed_override=(PRIVIO_UPDATE_FEED_URL="$PRIVIO_UPDATE_FEED_URL")
  print "Using overridden update feed: $PRIVIO_UPDATE_FEED_URL"
fi

xcodebuild \
  -project Privio.xcodeproj \
  -scheme Privio \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  build \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  "${feed_override[@]}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$code_sign_identity" \
  DEVELOPMENT_TEAM=""

# Re-sign only the host app with the local exception. Nested frameworks keep their
# normal signatures; the host may load them despite the lack of an Apple Team ID.
codesign --force --sign "$code_sign_identity" --options runtime \
  --entitlements "$local_entitlements" "$app_path"

# Fail early if Xcode ever falls back to ad-hoc signing.
actual_identity=$(codesign -dv --verbose=4 "$app_path" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)
if [[ "$actual_identity" != "$code_sign_identity" ]]; then
  print -u2 "Unexpected app signature: ${actual_identity:-none} (expected $code_sign_identity)"
  exit 4
fi

# Guardrail: verify the update feed actually baked into the app. A LOCAL test package
# (PRIVIO_UPDATE_FEED_URL overridden, normally to the localhost server) must never ship
# the production domain feed by accident - that produced a build that checked a not-yet-live
# feed and failed with "error fetching update info". Abort loudly on any mismatch.
baked_feed=$(/usr/bin/plutil -extract SUFeedURL raw "$app_path/Contents/Info.plist" 2>/dev/null || true)
print "Baked update feed: ${baked_feed:-<none>}"
if [[ -n "${PRIVIO_UPDATE_FEED_URL:-}" && "$baked_feed" != "$PRIVIO_UPDATE_FEED_URL" ]]; then
  print -u2 "Feed mismatch: baked '${baked_feed:-<none>}' but override requested '$PRIVIO_UPDATE_FEED_URL'."
  print -u2 "The command-line PRIVIO_UPDATE_FEED_URL override did not reach Info.plist - refusing to ship."
  exit 6
fi

rm -f "$pkg_path" "$component_path"

# Build the component with bundle relocation DISABLED. Otherwise macOS may "relocate"
# the install onto an already-registered copy of com.privio.Privio (e.g. a stale
# DerivedData path) instead of installing into /Applications as specified.
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
# Skrypt postinstall uruchamia aplikację po instalacji (musi być wykonywalny).
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

# System Installer requires an explicit Accept/Disagree decision before installation.
# License + welcome panes are rendered from Markdown to RTF (not shown as raw Markdown).
# Localized resource lookup selects the file matching the current macOS language.
rm -rf "$resources_dir"
mkdir -p "$resources_dir/pl.lproj" "$resources_dir/en.lproj"
md_rtf() {  # <source.md> <out.rtf> - render Markdown to a formatted RTF via HTML
  local tmp_html="${2%.rtf}.html"
  /usr/bin/python3 "$repo_dir/Scripts/md_to_html.py" "$1" > "$tmp_html"
  textutil -convert rtf -output "$2" "$tmp_html"
  rm -f "$tmp_html"
}
md_rtf "$repo_dir/EULA.md"                 "$resources_dir/pl.lproj/License.rtf"
md_rtf "$repo_dir/EULA.en.md"              "$resources_dir/en.lproj/License.rtf"
md_rtf "$repo_dir/Installer/Welcome.pl.md" "$resources_dir/pl.lproj/Welcome.rtf"
md_rtf "$repo_dir/Installer/Welcome.en.md" "$resources_dir/en.lproj/Welcome.rtf"

# Branding: the Privio logo MARK (just the "P", not the app-icon square) as a small
# bottom-left watermark - blue on the light installer, white on the dark installer.
# Regenerate these with: SCRATCH=/tmp swift Scripts/gen_icons.swift
cp "$repo_dir/Installer/logo-light.png" "$resources_dir/background.png"
cp "$repo_dir/Installer/logo-dark.png"  "$resources_dir/background-dark.png"

sed "s/__PRIVIO_VERSION__/$version/g" "$repo_dir/Installer/Distribution.xml" > "$distribution_path"

productbuild \
  --distribution "$distribution_path" \
  --resources "$resources_dir" \
  --package-path "$output_dir" \
  "$pkg_path"

pkgutil --check-signature "$pkg_path" || true
shasum -a 256 "$pkg_path"
print "Admin installer ready: $pkg_path"
print "Installer requires EULA acceptance and macOS administrator authorization."
print "Unsigned local test only; sign and notarize before public distribution."
