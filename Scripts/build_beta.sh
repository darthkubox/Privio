#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
derived_data="$repo_dir/.build/BetaDerivedData"
products_dir="$derived_data/Build/Products/Release"
app_path="$products_dir/Privio.app"
output_dir="$repo_dir/.build/beta"

cd "$repo_dir"
mkdir -p "$output_dir"

xcodegen generate
xcodebuild \
  -project Privio.xcodeproj \
  -scheme Privio \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=-

codesign --verify --deep --strict --verbose=2 "$app_path"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive_path="$output_dir/Privio-$version-unsigned-beta.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"

shasum -a 256 "$archive_path"
print "Unsigned beta ready: $archive_path"
print "This build is ad-hoc signed and not notarized. Do not present it as a public stable release."
