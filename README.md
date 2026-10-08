<div align="center">
  <img src="https://github.com/user-attachments/assets/cbd5c4e6-0262-4172-a19a-bf389f1557b4" width="128" alt="Medical app icon" />

  # Medical

  **Your medical history. In your hands.**

  A personal medical archive for macOS — documents, vaccinations, medicines, and notes, together in one place.

  No account. No cloud. Your records stay on your Mac.

  [Download](https://github.com/Ta2-me2/Medical/releases/latest) · [Build from source](#building) · [Report an issue](https://github.com/Ta2-me2/Medical/issues)
</div>

---

## About

Medical turns years of paperwork into an organized personal archive. Keep the original documents, connect them to records on a timeline, and find the details you need before your next appointment.

Everything lives in a folder you own: ordinary files and readable JSON. Your archive remains accessible even without the app.

> Built for macOS. A personal archive, not a clinical medical record system.

---

## Features

### Patient Profile

Keep essential information close at hand: your name, date of birth, languages, blood type, height, and weight. Record allergies and their severity, chronic conditions, and emergency contacts, with prominent medical alerts at the top of your profile.

<p align="center">
  <img src="https://github.com/user-attachments/assets/b7799d36-39ab-45d7-adf7-7d9eec9f01c7" width="92%" alt="Patient profile with personal information, medical alerts, vitals, allergies, and chronic conditions" />
</p>

### Dashboard

See what needs attention as soon as you open the app: documents waiting in your Inbox, vaccinations due, and medicines approaching or past their expiry dates. Pin important records for quick access.

<p align="center">
  <img src="https://github.com/user-attachments/assets/928b2829-c5a9-4009-a50b-21e91e24ea52" width="92%" alt="Dashboard showing unprocessed documents, vaccinations due, expired medicines, and pinned records" />
</p>

### Timeline

Browse your medical history on one continuous timeline, with a year rail for quick navigation. Keep consultations, tests, procedures, prescriptions, and vaccinations together with their dates, providers, findings, documents, and notes.

Filter the history, mark significant events or follow-ups, and preserve partial dates when an old record gives only a month or year.

<p align="center">
  <img src="https://github.com/user-attachments/assets/b7852113-6efd-44f0-a8bd-ce5cb46bb661" width="92%" alt="Medical timeline with year navigation, dated records, providers, findings, and attachments" />
</p>

### Inbox

Import your documents now and organize them at your own pace. Separate **Not Processed**, **Used**, and **Archived** files, see which documents already support a medical record, and open the linked record directly.

Original files are copied into the library, so filing a document never changes the source you imported.

<p align="center">
  <img src="https://github.com/user-attachments/assets/eed609de-8474-4b30-bd88-826de1efd123" width="92%" alt="Inbox with document status filters, file details, and links to medical records" />
</p>

### Documents

Browse the complete document library as a list or thumbnail grid. Search, sort, and filter files; check their format, page count, and the records that cite them. Archive-wide search is also available from the toolbar.

<p align="center">
  <img src="https://github.com/user-attachments/assets/21a49763-1da9-4a2e-9459-ae5e6c01fa19" width="92%" alt="Documents in a thumbnail grid with processing status, dates, and view controls" />
</p>

### Vaccinations

View your vaccination history **by vaccine or by date**, with dose details, manufacturers, batch numbers, and injection sites. Track the next dose using the booster intervals recorded in your archive.

Doses are grouped by what they protect against, so different product names can belong to one course with one booster schedule.

<p align="center">
  <img src="https://github.com/user-attachments/assets/f1725fbc-12aa-4349-af57-8f9ecc2bfc8c" width="92%" alt="Vaccination history with upcoming doses, vaccine groups, batch numbers, and booster intervals" />
</p>

### First Aid Kit

Keep an inventory of the medicines at home, organized by category, with expiry dates and attached documents. See what needs replacing and use a general checklist to spot categories missing from your kit.

The checklist suggests categories, not products or doses; a pharmacist can help you choose what fits your needs.

<p align="center">
  <img src="https://github.com/user-attachments/assets/ff030476-578a-4bd9-8304-9c88887a1b7a" width="92%" alt="First Aid Kit with missing categories, expiry alerts, and medicine cards" />
</p>

### Notes

Keep the details that do not fit a form: questions, observations, follow-up plans, or context about a document. Browse and filter notes in one place, with each note linked to its medical record and date.

<p align="center">
  <img src="https://github.com/user-attachments/assets/5438e70c-d173-441a-bfb1-f119a8ec9574" width="92%" alt="Notes linked to medical records, with dates and filtering" />
</p>

### Export

Prepare a **Doctor Report** or save the complete library as a ZIP archive for backup or transfer to another Mac.

- Choose the records and sections to include: chronology, vaccinations, findings and results, diagnoses, medications, full records, and source documents.
- Create a readable PDF report with the result tables you have entered in English.
- Include only the scanned pages your records cite — three relevant pages from a ninety-page document stay three pages in the export.
- Manage and switch between separate libraries through **Export → Libraries…**.

<p align="center">
  <img src="https://github.com/user-attachments/assets/56f7e046-eeb0-477f-ac1b-94a604e8aa43" width="92%" alt="Export options for a Doctor Report with selectable records, sections, and source documents" />
</p>

---

## Your Data

The library is a folder of readable JSON and original files:

```text
~/Library/Application Support/Medical/
└── Medical Library/
    ├── Archive.json    Medical records in readable JSON
    ├── Library.json    Library identity and format information
    ├── Originals/     Imported files, read-only and organized by year
    ├── Snapshots/     Previous versions of Archive.json
    └── Removed/       Originals removed from the archive, kept on disk
```

- **Preserved originals.** Imported files are copied, hashed, and made read-only. The app adds records without modifying those files.
- **Atomic saves.** Each save replaces the archive atomically and keeps the previous version in `Snapshots/`.
- **Recoverable removals.** Removing a document moves its original to `Removed/` rather than destroying it.
- **Portable libraries.** Move, rename, copy, or back up the folder with Time Machine. Keep several libraries side by side.

## Privacy

Medical has no networking code: no accounts, cloud sync, analytics, crash reporting, or AI. Your records stay on disk unless you choose to export or copy them.

The optional **John Appleseed** sample archive contains fictional data and is only added to an empty library.

---

## Building

Requires **macOS 26** and **Xcode 26 with Swift 6**. The current distribution is built from source.

```bash
git clone https://github.com/Ta2-me2/Medical.git
cd Medical
open Medical.xcodeproj
```

Press **⌘R** in Xcode to build and run.

<details>
<summary><strong>Command-line build and tests</strong></summary>

Build a release version:

```bash
xcodebuild -project Medical.xcodeproj -scheme Medical -configuration Release build
```

Run the model checks:

```bash
./Tests/run.sh
```

The checks cover document usage, date precision, booster schedules, library moves, backup round trips, and report contents. They compile with `swiftc` and need no simulator.

</details>

For the storage format and design decisions, see [ARCHITECTURE.md](ARCHITECTURE.md), written in Russian.

---

<div align="center">
  Made with care by <a href="https://github.com/Ta2-me2">Ta2</a>

  MIT License — see <a href="LICENSE">LICENSE</a>.
</div>
