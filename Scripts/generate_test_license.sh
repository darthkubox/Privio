#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
key_file=${PRIVIO_LICENSE_PRIVATE_KEY_FILE:-$HOME/.privio-license-signing-key.txt}
module_cache="$repo_dir/.build/SwiftModuleCache"
copy_to_clipboard=false
license_id=""

for argument in "$@"; do
  case "$argument" in
    --copy) copy_to_clipboard=true ;;
    --help|-h)
      print "Usage: Scripts/generate_test_license.sh [LICENSE_ID] [--copy]"
      print "Default private key file: $key_file"
      exit 0
      ;;
    *)
      if [[ -n "$license_id" ]]; then
        print -u2 "Only one LICENSE_ID may be provided."
        exit 2
      fi
      license_id="$argument"
      ;;
  esac
done

if [[ ! -f "$key_file" ]]; then
  print -u2 "Private signing key not found: $key_file"
  exit 1
fi

permissions=$(stat -f '%Lp' "$key_file")
if [[ "$permissions" != "600" && "$permissions" != "400" ]]; then
  print -u2 "Private key permissions are too broad ($permissions). Run: chmod 600 '$key_file'"
  exit 1
fi

if [[ -n "$license_id" ]]; then
  license=$(PRIVIO_LICENSE_PRIVATE_KEY_FILE="$key_file" swift -module-cache-path "$module_cache" "$repo_dir/Scripts/sign_license.swift" "$license_id")
else
  license=$(PRIVIO_LICENSE_PRIVATE_KEY_FILE="$key_file" swift -module-cache-path "$module_cache" "$repo_dir/Scripts/sign_license.swift")
fi

if $copy_to_clipboard; then
  print -n "$license" | pbcopy
  print "Test Pro license copied to clipboard."
else
  print "$license"
fi
