#!/bin/zsh
# Builds the export services on their own and exercises them against real files:
# a Doctor Report is generated, unzipped and read back, and a library backup is
# made and restored.
set -e
cd "$(dirname "$0")"
S=../Medical
swiftc -swift-version 6 -default-isolation MainActor -O \
  $S/Model/*.swift \
  $S/Persistence/ArchiveLocation.swift \
  $S/Persistence/ArchivePersistence.swift \
  $S/Persistence/FileArchivePersistence.swift \
  $S/Services/PDFReport.swift \
  $S/Services/DoctorReport.swift \
  $S/Services/LibraryBackup.swift \
  Report/main.swift -o /tmp/medicalid-reportchecks
/tmp/medicalid-reportchecks
