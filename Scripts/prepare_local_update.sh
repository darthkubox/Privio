#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=${1:-0.1.1}
build_number=${2:-2}
output_dir="$repo_dir/.build/local-update"
package_source="$repo_dir/.build/admin-installer/Privio-admin-install.pkg"
package_target="$output_dir/Privio-update.pkg"
sign_tool="$repo_dir/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

# Bake the localhost appcast into the package so a package-installed copy checks the
# local server (production feed is only used by un-overridden Release builds).
local_feed=${PRIVIO_UPDATE_FEED_URL:-http://127.0.0.1:8080/appcast.xml}

PRIVIO_VERSION="$version" PRIVIO_BUILD="$build_number" \
PRIVIO_UPDATE_FEED_URL="$local_feed" \
  "$repo_dir/Scripts/build_admin_installer.sh"

if [[ ! -x "$sign_tool" ]]; then
  print -u2 "Missing Sparkle sign_update tool. Build the Debug app once first."
  exit 2
fi

mkdir -p "$output_dir"
cp "$package_source" "$package_target"

signature=$($sign_tool -p "$package_target")
length=$(/usr/bin/stat -f %z "$package_target")
pub_date=$(LC_ALL=C date -R)

sed \
  -e "s|__VERSION__|$version|g" \
  -e "s|__BUILD__|$build_number|g" \
  -e "s|__SIGNATURE__|$signature|g" \
  -e "s|__LENGTH__|$length|g" \
  -e "s|__PUB_DATE__|$pub_date|g" \
  "$repo_dir/Installer/LocalAppcast.xml" > "$output_dir/appcast.xml"

print "Local update ready: $package_target"
print "Feed ready: $output_dir/appcast.xml"
print "Start it with: Scripts/serve_local_updates.sh"
