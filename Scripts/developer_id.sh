# Sourced by the release scripts (zsh). Resolves a Developer ID signing identity to its
# SHA-1 hash, accepting only certificates issued by the Developer ID G2 Sub-CA.
#
# Apple's original Developer ID Sub-CA expires on 2027-02-01, and installer packages
# signed with a certificate it issued stop installing on that date. G2 replacements
# carry the exact same name ("Developer ID Installer: Name (TEAM)"), so a name match
# with `head -1` silently picks the old certificate while both sit in the keychain
# (the keychain lists the older ones first). Matching by issuer keeps the choice
# deterministic; signing by hash keeps codesign/productbuild from guessing by name.

# developer_id_identity <Application|Installer> [team-id]
# Prints the SHA-1 of the valid G2 identity with the latest expiry, or fails.
developer_id_identity() {
  local kind=$1 team=${2:-} hash pem issuer end_date end best= best_end=0 best_date=
  local -a policy hashes
  # Installer certs are not under the codesigning policy; query the default list.
  [[ $kind == Application ]] && policy=(-p codesigning)
  hashes=(${(fu)"$(security find-identity -v $policy \
    | grep -F "\"Developer ID $kind: " | grep -F "(${team}" \
    | grep -oE '[0-9A-F]{40}')"})

  for hash in $hashes; do
    pem=$(security find-certificate -a -Z -p -c "Developer ID $kind: " \
      | awk -v h=$hash '/^SHA-1 hash:/ {on = ($3 == h)}
          on && /BEGIN CERTIFICATE/ {p = 1}  p {print}  /END CERTIFICATE/ {p = 0}')
    issuer=$(print -r -- "$pem" | /usr/bin/openssl x509 -noout -issuer -nameopt RFC2253)
    [[ $issuer == *,OU=G2,* ]] || continue
    end_date=$(print -r -- "$pem" | /usr/bin/openssl x509 -noout -enddate)
    end=$(date -j -f "%b %d %T %Y %Z" "${end_date#notAfter=}" +%s)
    if (( end > best_end )); then
      best=$hash best_end=$end best_date=$(date -j -r $end +%Y-%m-%d)
    fi
  done

  if [[ -z $best ]]; then
    print -u2 "No valid 'Developer ID $kind' identity${team:+ for team $team} issued by the G2 Sub-CA."
    print -u2 "Create one at developer.apple.com (Certificates → +, choose \"G2 Sub-CA\")."
    print -u2 "Certificates from the previous Sub-CA stop working on 2027-02-01."
    return 1
  fi
  print -u2 "Developer ID $kind: ${best[1,8]}… (G2, expires $best_date)"
  if (( best_end - $(date +%s) < 30 * 86400 )); then
    print -u2 "WARNING: Developer ID $kind certificate expires in under 30 days ($best_date)."
  fi
  print -r -- $best
}
