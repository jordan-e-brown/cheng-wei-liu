# 成为流 — Chéngwéi Liú

Native iPhone learning app with two isolated projects:

- **快学 — Kuài Xué**: Anki-based self-study + rotating WidgetKit flashcards.
- **汉语谈话 — Hànyǔ Tánhuà**: persistent Mandarin language-partner conversations. It does not read Anki data.

Current repo version: **0.2.0**.

## Intended development environment

This repository is configured for the current machine/device baseline:

- Intel Mac
- macOS 26.2+
- Xcode 26.6 installed as the Apple toolchain
- VS Code or another editor as the day-to-day IDE
- iPhone on iOS 26.6.1 for physical-device testing

Xcode itself does not need to be your editor, but Apple's Xcode toolchain is required to compile, sign, install, and ship a WidgetKit iPhone app.

## Repository layout

```text
App/                  SwiftUI application
  QuickStudy/         快学
  Conversation/       汉语谈话
  Security/           Keychain helper
  Settings/
Shared/               models and App Group storage shared with widget
Widget/               WidgetKit extension
Backend/              FastAPI + OpenAI + Headroom + SQLite
Tools/AnkiExporter/   AnkiConnect JSON exporter
Config/               bundle/App Group build identifiers
docs/                 architecture and pedagogy contracts
scripts/              setup, diagnostics, LAN backend runner
```

## 1. Clone and prepare

```bash
git clone <your-repo-url> ChengWeiLiu
cd ChengWeiLiu
./scripts/setup_vscode_intel.sh
make doctor
```

Or, if you downloaded this source archive directly:

```bash
cd ChengWeiLiu
./scripts/setup_vscode_intel.sh
```

The project uses **XcodeGen**, so the generated `ChengWeiLiu.xcodeproj` is intentionally ignored by git.

## 2. Configure Apple identifiers

Edit `Config/Base.xcconfig`:

```text
APP_BUNDLE_ID = com.yourname.chengweiliu
WIDGET_BUNDLE_ID = com.yourname.chengweiliu.widget
APP_GROUP_ID = group.com.yourname.chengweiliu
```

Create the same App Group in your Apple Developer signing configuration for both the app and widget targets.

Generate the Xcode project:

```bash
make generate
```

## 3. Build without using the Xcode IDE

Simulator build:

```bash
make build-sim
```

On an Intel Mac, if you need a compatible iOS Simulator runtime:

```bash
make simulator-runtime
```

List attached Apple devices:

```bash
make list-devices
```

Signed generic device build:

```bash
make build-device TEAM_ID=YOUR_APPLE_TEAM_ID
```

For initial WidgetKit, App Group, local-network, and later microphone testing, a physical iPhone is the preferred target.

## 4. Export the two Anki decks

Keep Anki Desktop open with AnkiConnect enabled, then:

```bash
cd Tools/AnkiExporter
python3 anki_widget_export.py \
  --deck "Chinese Grammar (汉语 语法)" \
  --deck "Neri's Chinese Course" \
  --output anki-widget.json
```

Transfer the JSON file to the iPhone and import it from **成为流 → 快学**.

The widget prioritizes those two decks and alternates deck exposure so the larger deck does not automatically dominate every slot.

## 5. Widget rotation

In **设置**, select:

```text
15 min · 30 min · 1 hr · 2 hr · 3 hr · 6 hr · 12 hr
```

This drives WidgetKit's requested next timeline refresh. iOS still controls the actual redraw time.

Tapping a displayed card deep-links into the exact deck/note in 快学.

## 6. Run 汉语谈话

Create the Python environment:

```bash
make backend-install
cp Backend/.env.example Backend/.env
```

Edit `Backend/.env` and provide `OPENAI_API_KEY`.

The current dependency baseline is:

- OpenAI Python SDK `>=3.2,<4`
- Headroom `>=0.36,<0.37`

For Simulator-only development:

```bash
make backend
```

For a physical iPhone on the same Wi-Fi:

```bash
make backend-lan
```

Then find your Mac's LAN IP and set **成为流 → 设置 → 汉语谈话 Backend URL** to, for example:

```text
http://192.168.1.20:8000
```

For optional development authentication, set `BACKEND_BEARER_TOKEN` in `Backend/.env` and enter the same token in app settings. The phone stores it in Keychain.

Do not expose this development HTTP server to the public internet. Use HTTPS and proper authentication before remote deployment.

## 7. Headroom compression policy

汉语谈话 preserves linguistic evidence rather than compressing everything indiscriminately:

```python
result = compress(
    provider_messages,
    model=HEADROOM_MODEL,
    compress_user_messages=False,
    compress_system_messages=False,
    protect_recent=10,
    target_ratio=0.5,
    min_tokens_to_compress=250,
)
```

Learner messages stay verbatim. Older assistant/context material is eligible for compression. If Headroom fails, conversation continues without compression.

## 8. Tests

```bash
make test-backend
```

The current tests cover SQLite persistence/reopening/memory reset and enforce the critical 汉语谈话 prompt boundary from 快学.

## Product boundary

**快学 and 汉语谈话 must remain separate.** Anki inputs are self-study inputs only. Conversation history/memory never targets, retrieves, or evaluates Anki vocabulary.

See:

- `docs/ARCHITECTURE.md`
- `docs/PEDAGOGY.md`

## Next milestones

1. Build/install on the physical iPhone and remediate any signing/runtime issues.
2. Add OpenAI Realtime voice to 汉语谈话.
3. Add native pronunciation/tones feedback.
4. Build the Anki Desktop companion bridge for collection-mutating add-on operations.
5. Reimplement selected UI-only Anki add-on capabilities natively in 快学.
6. Add TestFlight CI/signing after the app is stable on-device.
