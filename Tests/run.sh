#!/bin/zsh
# Compiles the domain model on its own and runs the checks in main.swift.
# The model has no framework dependencies, so it can be verified without
# building or launching the app.
set -e
cd "$(dirname "$0")"
swiftc -swift-version 6 -default-isolation MainActor -O \
  ../Medical/Model/*.swift ../Medical/Features/Search/SearchService.swift \
  ../Medical/Persistence/*.swift \
  ../Medical/Services/LibraryBackup.swift ../Medical/Services/LibraryDirectory.swift \
  ../Medical/Services/PDFReport.swift ../Medical/Services/DoctorReport.swift \
  LibraryLocation.swift LibraryChoosing.swift LibraryRestore.swift ReportSections.swift \
  FirstAidKit.swift DocumentUsage.swift main.swift -o /tmp/medicalid-modelchecks

# The library-location checks move folders around, so they are given a home
# directory of their own to move them in. Nothing here can reach the real one.
STUB_HOME="$(mktemp -d)/home"
mkdir -p "$STUB_HOME/Documents" "$STUB_HOME/Library/Application Support"
# Runs on the way out whatever happened, a failed check included.
#
# The checks write a few defaults, and cfprefsd puts them in the real home
# whatever CFFIXED_USER_HOME says. Removing the file straight after the run is
# not enough: cfprefsd writes it back a moment later from what it still has
# cached. `defaults delete` goes through cfprefsd itself, so it lands after
# those pending writes rather than before them.
cleanup() {
  rm -rf "$(dirname "$STUB_HOME")"
  # `|| true`: under `set -e` a failing step would end the cleanup early, and
  # `defaults delete` fails whenever there is nothing left to delete.
  defaults delete medicalid-modelchecks >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/medicalid-modelchecks.plist"
}
trap cleanup EXIT

CFFIXED_USER_HOME="$STUB_HOME" /tmp/medicalid-modelchecks
