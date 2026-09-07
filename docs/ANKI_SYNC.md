# JSON import and Anki Desktop return flow — v0.3

## Import on iPhone, including iOS 26.6

The app and widget support iOS 17 and later, including iOS 26.6. Keep the minimum deployment target at 17.0; it is a minimum, not a maximum OS version. Both targets use the same App Group and current installed SDK. This checkout was built with Xcode 26.6, whose installed SDK/runtime reports iOS 26.5. An actual iOS 26.6 device run still requires signing and an unlocked connected phone.

1. Open Anki Desktop in the source profile, with AnkiConnect enabled.
2. Export from the repository root:

   ```bash
   python3 Tools/AnkiExporter/anki_widget_export.py \
     --deck "Chinese Grammar (汉语 语法)" \
     --deck "Neri's Chinese Course" \
     --output anki-widget.json
   ```

3. Transfer the JSON through AirDrop or iCloud Drive.
4. In 成为流 → 快学, tap **Import Anki JSON** and choose the downloaded JSON in Files. Opening/sharing a JSON file with 成为流 also starts import.
5. Wait for the success alert showing the imported deck/note counts. Add the 成为流 widget to the Home Screen.

CrowdAnki deck JSON is also supported. The importer reconstructs field names from `note_models[].flds`, links `note_model_uuid`, preserves note GUIDs, and flattens recursive `children` into `Parent::Child` deck names. Transfer the complete deck JSON, including models. It does not render external audio/images or arbitrary Anki templates. Native `.apkg` and `.colpkg` import are not implemented in this checkout; JSON is the working transfer path.

Legacy normalized schema 1 remains supported. The desktop exporter now emits schema 2, including the source profile and card IDs. It retains raw named fields. A note with several card templates is shown as a note-level exercise; the app does not guess which card to grade.

Imports validate the entire file before atomically replacing the shared snapshot. Unsupported schemas, missing models, duplicate note IDs within a deck, empty imports, and invalid fields fail with an explanation. The last good snapshot and all activity remain intact. The file limit is 50 MB. Import parsing and file-provider reads run off the main thread while the security scope remains active.

## Widget and app activity

- The widget supplies a day of future entries at the chosen interval, with balanced exposure across all nonempty imported decks.
- **Reveal** shows the answer and records a widget event. **Next** advances and records a skip. Tapping the card opens that exact note and records the widget tap.
- The app starts with the answer hidden. Reveal, navigation, and Again/Hard/Good/Easy ratings are recorded. A rating is saved before the UI acknowledges it, and a second tap cannot rate the same presentation again.
- Widget timeline generation is not logged as a display/view event: WidgetKit does not prove that a generated entry was actually seen.
- Widget actions carry a content-specific token. Stale controls cannot change a different card after a refresh/import. Retried actions use a stable event ID.
- Each immutable event is an atomic JSON file in the App Group. A cross-process file lock protects device identity and widget mutations. A damaged event makes export fail visibly rather than silently omitting it.
- Import and export never delete activity. Conversation transcripts and conversation memory remain isolated from this ledger.

WidgetKit decides actual rendering times; a requested interval is not an exact refresh guarantee. See [Apple's timeline documentation](https://developer.apple.com/documentation/widgetkit/timeline).

## Export back to Desktop

In 快学, select **Export study activity**, save the JSON in Files/iCloud Drive, and transfer it to the Mac. From the repo root:

```bash
# Validate only: no Anki access or mutations.
python3 Tools/AnkiExporter/anki_activity_import.py \
  ~/Downloads/chengweiliu-activity.json --profile "User 1"

# Archive events in the local bridge journal and add activity tags to Anki notes.
python3 Tools/AnkiExporter/anki_activity_import.py \
  ~/Downloads/chengweiliu-activity.json --profile "User 1" \
  --apply --receipt ~/Downloads/chengweiliu-receipt.json
```

Replace `User 1` with the exact source Anki profile. Keep that profile open throughout the run. A profile name is a local identity guard, not a globally unique collection ID: use the original collection, not a different collection with the same profile name.

Activity tags are `chengweiliu::opened`, `chengweiliu::revealed`, `chengweiliu::skipped`, and `chengweiliu::review`. Full timestamps, elapsed time, rating, device, and source remain in the SQLite bridge journal at `~/.chengweiliu/activity.sqlite3` and in the iOS JSON. These tags are cumulative indicators, not review counts. Repeated exports do not duplicate reviews; adding the same tags is idempotent.

To apply eligible ratings as Anki scheduler answers, explicitly add:

```bash
python3 Tools/AnkiExporter/anki_activity_import.py \
  ~/Downloads/chengweiliu-activity.json --profile "User 1" \
  --apply --apply-reviews --receipt ~/Downloads/chengweiliu-receipt.json
```

**This grades cards at desktop sync time. It does not reconstruct historical revlog times, elapsed review time, or historical FSRS scheduling.** Avoid reviewing the same cards independently on desktop before applying an offline batch; automatic scheduling conflict reconciliation is not provided. Only events with a source profile and exactly one known card ID can be graded. GUID-only CrowdAnki notes, legacy notes without card IDs, and multi-template notes are practice-only. Suspended/buried cards, deleted cards, wrong profiles, changed deck membership, and card/note mismatches are blocked.

The bridge uses AnkiConnect's supported `notesInfo`, `findNotes`, `addTags`, `cardsInfo`, `getActiveProfile`, and `answerCards` operations. It does not open or edit Anki's collection database. The bridge journal is a separate SQLite file. See the [AnkiConnect project](https://git.sr.ht/~foosoft/anki-connect).

## Interrupted review requests

A remote `answerCards` call and a local journal commit cannot be one atomic transaction. Before sending a rating, the bridge durably marks it `in_flight`. If the response is lost, the bridge will not automatically send it again. Its receipt reports the event as failed/uncertain, even if Anki actually applied it.

Inspect the card's review history in Anki. After determining the outcome, resolve that exact event:

```bash
# Only if the review was applied in Anki:
python3 Tools/AnkiExporter/anki_activity_import.py --profile "User 1" \
  --apply --resolve-review EVENT_ID --resolution applied

# Only if it definitely was not applied, allow a later retry:
python3 Tools/AnkiExporter/anki_activity_import.py --profile "User 1" \
  --apply --resolve-review EVENT_ID --resolution retry
```

Then rerun the original import command. Keep the journal; deleting it removes duplicate protection. Receipts are diagnostic files and are not currently imported back into iOS. Device events remain available for re-export.

## Reproduce validation

```bash
make test-anki
make test-ios DEVICE_ID=209F1CB4-2618-4A26-B02B-FCCD3E573A18
make build-device-unsigned
```

Build outputs default to `/tmp/ChengWeiLiuDerivedData` to avoid iCloud/Finder metadata causing code-signing failures in a synced Documents folder. Override `DERIVED` if needed.

Simulator builds/tests use local ad hoc signing (`CODE_SIGN_IDENTITY=-`) so the app and widget receive their App Group entitlements. No Apple account is needed for simulator signing. Disabling signing entirely may compile but makes shared-container import fail at runtime.

Use `make list-sims` to select a simulator installed on your Mac. Xcode tests cover import validation, File Provider reading, CrowdAnki field mapping, atomic replacement, activity retention, widget timelines, concurrency, a 20,000-note fixture, and the app study flow. The desktop tests use a simulated AnkiConnect service, including a response lost after the remote review succeeds. They do not alter a real Anki collection.
