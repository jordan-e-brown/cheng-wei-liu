# 0.3.0 — JSON import, interactive widgets, and activity return

- Import normalized schema 1/2 and CrowdAnki JSON with nested decks, field mapping, validation, and atomic replacement.
- Handle JSON opened from Files/AirDrop and coordinate cloud file reads off the UI thread.
- Add widget Reveal/Next, content-specific action tokens, and a day of future timeline entries.
- Persist app/widget events independently of deck snapshots and export activity JSON from iOS.
- Add a journaled AnkiConnect desktop bridge with optional grading and explicit recovery for uncertain remote outcomes.
- Add Xcode import/rotation/concurrency/large-deck/UI tests and mocked desktop round-trip tests.
- Retain iOS 17+ deployment compatibility, including iOS 26.6; bump app/widget version to 0.3.0 (3).

# Changelog

## 0.2.0 — 2026-08-25

- Renamed product to **成为流 — Chéngwéi Liú**.
- Renamed projects to **快学 — Kuài Xué** and **汉语谈话 — Hànyǔ Tánhuà**.
- Replaced the tab-first prototype with a branded project home screen that shows pinyin subtitles.
- Added configurable bundle/App Group identifiers through `Config/Base.xcconfig`.
- Added App Group WidgetKit storage and exact-card widget deep links.
- Kept the discrete 15m/30m/1h/2h/3h/6h/12h widget refresh selector.
- Added local-network iPhone development configuration.
- Added Keychain storage for an optional backend bearer token.
- Added persistent 汉语谈话 transcript history and inspectable/resettable learner memory.
- Preserved learner messages from Headroom compression and protected the ten most recent messages.
- Updated backend dependency ranges for OpenAI Python 3.x and Headroom 0.36.x.
- Added the AnkiConnect exporter to the repository.
- Added backend tests, architecture/pedagogy docs, VS Code tasks, and GitHub backend CI.
