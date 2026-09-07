# v0.3 validation — 2026-09-07

## Results

| Check | Result |
| --- | --- |
| Xcode simulator build, app and widget | Passed |
| Xcode iOS tests, iPhone 17 Pro / iOS 26.5 | 16 passed |
| Xcode app UI flow | 1 passed |
| Python Anki exporter / activity bridge tests | 13 passed |
| Existing conversation backend tests | 3 passed |
| Generic physical-iPhone arm64 build, unsigned | Passed |
| Swift simulator activity JSON → Python bridge → repeat same export | Passed: 2 events, 1 remote rating total |
| Physical iOS 26.6 installation/runtime | Not verified; device access was not approved |
| Real Anki Desktop collection mutations | Not performed; bridge tested with a simulated AnkiConnect service |

Xcode reports version 26.6 (17F113). Installed iPhone/device and Simulator SDKs report 26.5. App and widget retain a minimum deployment target of iOS 17, which permits installation on iOS 26.6. This validates compilation and the available simulator, not an actual iOS 26.6 device run.

## Import and widget backtests

- Coordinated file reading → import validation → atomic shared-format snapshot → widget selection/timeline.
- Normalized schemas 1/2, numeric IDs, optional tags, UTF-8 BOM, Chinese/pinyin text, HTML/cloze cleanup.
- CrowdAnki root model lookup, ordered fields, recursive subdeck names, GUID preservation.
- Missing models, incorrect field counts, duplicate notes, malformed JSON, unknown schemas, and empty imports rejected while retaining the last good snapshot.
- Reimport preserves existing study history.
- A 20,000-note input imports and generates 97 distinct widget entries at a 15-minute interval; measured about 3.4 seconds in the simulator test including fixture construction, validation, and storage.
- Every refresh interval produces ordered boundary-aligned timelines, and all imported nonempty decks receive exposure.
- Reveal/Next persist widget events once; stale tokens and retry after an interrupted state write do not duplicate events.
- 100 concurrent app/widget writes retain 100 unique events and one device identity after reopening/exporting.
- Corrupted event files produce a visible export error instead of dropping history.

## UI and desktop round trip

The UI test imports bundled sample decks, reveals a card, saves Good, opens the activity export sheet, relaunches the app, and verifies the activity count persisted. It also captures the revealed card with its saved rating. File Provider reading and the actual serialized export payload are exercised separately by the integration tests.

The Swift contract test writes a synthetic numeric-ID deck, reads the snapshot with the widget selector, records widget reveal and app rating events, then exports JSON from the simulator. The Python bridge successfully reads that exact JSON, maps the note/card against a simulated Anki service, applies the rating, and skips the review on replay. The remote rating counter remains 1.

The desktop tests also cover a response lost after Anki applied a rating, manual resolution, wrong profile, card/note mismatch, suspended cards, GUID-only practice, conflicting event IDs, invalid batches, and older/out-of-order exports. An uncertain review blocks later ratings until reconciled.

## Runtime fixes found by testing

The original `CODE_SIGNING_ALLOWED=NO` simulator workflow compiled but failed UI import because it omitted usable App Group entitlements. Simulator builds/tests now use local ad hoc signing. Existing build products under synced Documents also had Finder metadata that blocked code signing; Makefile build output now defaults to `/tmp/ChengWeiLiuDerivedData`.

The generic iPhone build exposed missing orientation metadata; the final project explicitly declares supported orientations.

## Reproduction and local evidence

See [ANKI_SYNC.md](ANKI_SYNC.md) for the transfer/return workflow and commands. Local generated evidence is under `build/validation/` (ignored by Git), including the exact Swift export and the desktop round-trip result. The Xcode test result is `/tmp/ChengWeiLiuDerivedData/Logs/Test/Test-ChengWeiLiu-2026.09.07_00-07-53--0500.xcresult`.

Widget rendering on a physical Home Screen, AirDrop/iCloud transfer on a real phone, and real Anki scheduler integration remain manual device/desktop acceptance checks. Scheduled widget entries are not claimed as observed impressions. Historical FSRS/revlog reconstruction, native APKG/media import, cloud transport, and receipt ingestion on iOS are outside this version.
