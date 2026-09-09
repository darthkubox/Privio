#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
update_dir="$repo_dir/.build/local-update"

if [[ ! -f "$update_dir/appcast.xml" || ! -f "$update_dir/Privio-update.pkg" ]]; then
  print -u2 "No local update found. Run Scripts/prepare_local_update.sh VERSION BUILD first."
  exit 2
fi

print "Serving Privio updates at http://127.0.0.1:8080/appcast.xml"
print "Press Control-C to stop."
cd "$update_dir"
exec /usr/bin/python3 -m http.server 8080 --bind 127.0.0.1
