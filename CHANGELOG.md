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
