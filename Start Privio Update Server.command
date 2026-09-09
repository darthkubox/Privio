#!/bin/zsh
# Double-click to start Privio's LOCAL update server (Sparkle appcast on 127.0.0.1:8080).
# Keep this window open while you click "Check for Updates…" inside Privio.
# This is for local development testing only - public updates use HTTPS.
set -uo pipefail

# The command lives in the repository root. Resolve from its own location so a
# moved/copied project never serves an update package from an obsolete checkout.
repo_dir=${0:A:h}
cd "$repo_dir"
update_dir="$repo_dir/.build/local-update"
sign_tool="$repo_dir/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

banner() {
  print "────────────────────────────────────────────"
  print "  Privio - Local Update Server"
  print "────────────────────────────────────────────"
}
clear 2>/dev/null || true
banner

ensure_sign_tool() {
  if [[ ! -x "$sign_tool" ]]; then
    print "First-time setup: building Privio once to fetch the Sparkle signing tool…"
    print "(this can take a minute)"
    if ! xcodebuild -project Privio.xcodeproj -scheme Privio -configuration Debug \
        -destination 'platform=macOS' -derivedDataPath .build/DerivedData build >/dev/null 2>&1; then
      print "Build failed. Open Privio.xcodeproj in Xcode to see the error."
      print "Press Return to close."; read _; exit 1
    fi
  fi
}

# Stage an update if none exists yet.
if [[ ! -f "$update_dir/appcast.xml" || ! -f "$update_dir/Privio-update.pkg" ]]; then
  print "No update is staged yet - let's build one."
  print ""
  print -n "Version to publish [0.1.1]: "; read ver; ver=${ver:-0.1.1}
  print -n "Build number (must keep increasing) [2]: "; read bld; bld=${bld:-2}
  ensure_sign_tool
  if ! ./Scripts/prepare_local_update.sh "$ver" "$bld"; then
    print "Preparation failed. Press Return to close."; read _; exit 1
  fi
  clear 2>/dev/null || true
  banner
fi

ver=$(/usr/bin/python3 -c "import re;print(re.search(r'shortVersionString=\"([^\"]+)\"', open('$update_dir/appcast.xml').read()).group(1))" 2>/dev/null || echo "?")
print "✓ Serving Privio update  →  version $ver"
print "  Feed URL:  http://127.0.0.1:8080/appcast.xml"
print ""
print "Now open Privio → Settings (or the menu-bar icon) and click"
print "\"Check for Updates…\".  Leave this window open during the update."
print ""
print "Press Control-C here to stop the server when you're done."
print "────────────────────────────────────────────"

cd "$update_dir"
exec /usr/bin/python3 -m http.server 8080 --bind 127.0.0.1
