#!/bin/zsh
set -euo pipefail

# Generate the production Sparkle appcast for a notarized Privio package.
#
# The appcast is hosted on the owned domain (https://priviolock.com/updates/appcast.xml);
# the .pkg it references lives wherever the enclosure URL points (default plan: a GitHub
# Release asset). This script computes the EdDSA signature + byte length of the package
# built by build_release_pkg.sh and fills Installer/ProdAppcast.xml.
#
# Usage:
#   Scripts/make_appcast.sh <VERSION> <BUILD> <ENCLOSURE_URL> [PKG_PATH]
# Example:
#   Scripts/make_appcast.sh 0.1.0 1 \
#     https://github.com/darthkubox/Privio/releases/download/v0.1.0/Privio-0.1.0.pkg

repo_dir=${0:A:h:h}
version=${1:?Usage: make_appcast.sh VERSION BUILD ENCLOSURE_URL [PKG_PATH]}
build_number=${2:?Usage: make_appcast.sh VERSION BUILD ENCLOSURE_URL [PKG_PATH]}
enclosure_url=${3:?Usage: make_appcast.sh VERSION BUILD ENCLOSURE_URL [PKG_PATH]}
output_dir="$repo_dir/.build/release-pkg"
package_target=${4:-$output_dir/Privio-$version.pkg}
sign_tool="$repo_dir/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

if [[ "$enclosure_url" != https://* ]]; then
  print -u2 "Enclosure URL must be HTTPS (public Sparkle updates are HTTPS-only): $enclosure_url"
  exit 2
fi
if [[ ! -f "$package_target" ]]; then
  print -u2 "Package not found: $package_target"
  print -u2 "Build it first: Scripts/build_release_pkg.sh"
  exit 3
fi
if [[ ! -x "$sign_tool" ]]; then
  print -u2 "Missing Sparkle sign_update tool ($sign_tool)."
  print -u2 "Build the Debug app once so the Sparkle SPM artifact is fetched:"
  print -u2 "  xcodebuild -project Privio.xcodeproj -scheme Privio -destination 'platform=macOS' build"
  exit 4
fi

mkdir -p "$output_dir"
signature=$($sign_tool -p "$package_target")
length=$(/usr/bin/stat -f %z "$package_target")
pub_date=$(LC_ALL=C date -R)

# sed uses '|' as delimiter because the enclosure URL contains slashes.
sed \
  -e "s|__VERSION__|$version|g" \
  -e "s|__BUILD__|$build_number|g" \
  -e "s|__SIGNATURE__|$signature|g" \
  -e "s|__LENGTH__|$length|g" \
  -e "s|__PUB_DATE__|$pub_date|g" \
  -e "s|__ENCLOSURE_URL__|$enclosure_url|g" \
  "$repo_dir/Installer/ProdAppcast.xml" > "$output_dir/appcast.xml"

print "Appcast ready: $output_dir/appcast.xml"
print "  version   : $version (build $build_number)"
print "  enclosure : $enclosure_url"
print "  length    : $length bytes"
print "Upload it to https://priviolock.com/updates/appcast.xml (OVH www/updates/)."
