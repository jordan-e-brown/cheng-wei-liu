# Anki → 快学 exporter

Run this while Anki Desktop and AnkiConnect are open.

```bash
python3 anki_widget_export.py --list-decks
python3 anki_widget_export.py \
  --deck "Chinese Grammar (汉语 语法)" \
  --deck "Neri's Chinese Course" \
  --output anki-widget.json
```

Transfer `anki-widget.json` to the iPhone (AirDrop/iCloud Drive) and import it from **成为流 → 快学**.

This is intentionally a read-only bridge in v0.2. Anki remains the source of truth for scheduling and add-on state.
