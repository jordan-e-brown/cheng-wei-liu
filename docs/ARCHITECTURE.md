# Architecture

## Product boundary

**成为流 — Chéngwéi Liú** contains two deliberately isolated projects.

### 快学 — Kuài Xué

Offline Anki self-study with a file-based desktop activity bridge.

- Imports normalized JSON from Anki Desktop/AnkiConnect or complete CrowdAnki deck JSON.
- Shares imported data with the WidgetKit extension through an App Group.
- Rotates cards passively at a user-selected 15m / 30m / 1h / 2h / 3h / 6h / 12h interval request.
- iOS does not modify Anki scheduler state; the desktop bridge can explicitly apply eligible ratings through AnkiConnect at sync time.
- Anki Desktop remains authoritative for FSRS, add-ons, collection changes, and sync.

Future add-on capability work remains desktop-bridged where the original add-on mutates the Anki collection or depends on Python/Qt. Pure presentation/gamification features can be reimplemented natively.

### 汉语谈话 — Hànyǔ Tánhuà

A language-partner project only.

- No deck access.
- No Anki vocabulary targeting.
- No due-card injection.
- No automatic flashcard creation.
- Persistent conversation transcripts and a separate cross-session learner memory.
- OpenAI Responses API on the server side.
- Headroom compression is applied only to older model context; exact learner utterances remain uncompressed.

## Data flow

```text
Anki Desktop + AnkiConnect
        |
        | Tools/AnkiExporter/anki_widget_export.py
        v
  anki-widget.json
        |
        v
  iPhone 快学 app ---- App Group ---- WidgetKit
        |                  |
        |             immutable study events
        v
  activity JSON → Desktop bridge journal → AnkiConnect tags / optional ratings


  iPhone 汉语谈话
        |
        | HTTPS / LAN HTTP in development
        v
  FastAPI backend
        |-- SQLite conversation + learner memory
        |-- Headroom context compression
        `-- OpenAI Responses API
```

The two branches do not share pedagogical state.

## Security

- Never embed `OPENAI_API_KEY` in the iOS binary.
- The backend may require `BACKEND_BEARER_TOKEN`; the iOS app stores that token in Keychain.
- Cleartext HTTP is allowed only for local-network development. Production deployment should use HTTPS and authenticated server access.
- App Group access is limited to the app and its widget extension.

## Version 0.2 scope

Implemented:

- branded SwiftUI shell
- pinyin subtitles
- Anki JSON import
- exact-card widget deep link
- App Group shared storage
- discrete widget refresh interval selector
- persistent text conversation
- conversation memory inspection/reset
- optional backend bearer auth
- Headroom compression safeguards
- XcodeGen + VS Code/CLI workflow

Deferred:

- Realtime voice/WebRTC
- pronunciation analysis
- Historical Anki review/scheduling reconciliation
- FSRS Helper actions
- AnkiCollab bridge
- HyperTTS bridge
- native Life Drain / Speed Focus / review heatmap
- TestFlight/App Store automation

## Version 0.3

See [ANKI_SYNC.md](ANKI_SYNC.md) for the JSON format, immutable event ledger, duplicate protection, interrupted-review reconciliation, iOS 26.6 compatibility, and repeatable validation commands. Native APKG ingestion and cloud sync remain deferred.
