#!/bin/zsh
set -u

repo_dir=${0:A:h:h}
cd "$repo_dir"
issues=0

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print "BLOCKED: missing command: $1"
    issues=$((issues + 1))
  fi
}

check_command xcodegen
check_command xcodebuild

if ! security find-identity -p codesigning -v 2>/dev/null | grep -q 'Developer ID Application'; then
  print 'BLOCKED: Developer ID Application certificate is not installed.'
  issues=$((issues + 1))
fi

if rg -n '\[\.\.\.\]|to be filled|do uzupełnienia|Draft pending legal review|Draft do przeglądu prawnego' \
    EULA.md EULA.en.md LICENSE.md >/dev/null; then
  print 'BLOCKED: legal documents still contain draft notices or placeholders.'
  issues=$((issues + 1))
fi

if [[ ! -f Docs/PRIVACY_MODEL.md ]]; then
  print 'BLOCKED: privacy documentation is missing.'
  issues=$((issues + 1))
fi

if [[ ! -f .github/workflows/ci.yml ]]; then
  print 'BLOCKED: CI workflow is missing.'
  issues=$((issues + 1))
fi

if (( issues > 0 )); then
  print "Release readiness: $issues blocker(s)."
  exit 1
fi

print 'Release readiness: prerequisites present. Run the full build, tests and manual matrix.'
