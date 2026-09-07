#!/usr/bin/env python3
"""Export one or more Anki decks to a compact JSON file for 成为流 → 快学.

Requires:
  - Anki Desktop running
  - AnkiConnect add-on enabled (default endpoint http://127.0.0.1:8765)

Examples:
  python anki_widget_export.py --list-decks
  python anki_widget_export.py --deck "HSK 1" --output anki-widget.json
  python anki_widget_export.py --deck "Mandarin::HSK 1" --deck "Mandarin::HSK 2" -o anki-widget.json
  python anki_widget_export.py --all -o anki-widget.json
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Dict, Iterable, List

ANKICONNECT_URL = "http://127.0.0.1:8765"
API_VERSION = 6


class _TextExtractor(HTMLParser):
    BLOCK_TAGS = {"br", "div", "p", "li", "tr"}

    def __init__(self) -> None:
        super().__init__()
        self.parts: List[str] = []

    def handle_starttag(self, tag: str, attrs: List[tuple[str, str | None]]) -> None:
        if tag.lower() in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in {"div", "p", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def clean_anki_text(value: str) -> str:
    """Convert common Anki HTML/cloze content to compact readable plain text."""
    if not value:
        return ""

    # Remove Anki sound markers from text-only widget output.
    value = re.sub(r"\[sound:[^\]]+\]", "", value, flags=re.IGNORECASE)

    # Reveal cloze answers while dropping optional hints.
    value = re.sub(r"\{\{c\d+::(.*?)(?:::(.*?))?\}\}", r"\1", value, flags=re.DOTALL)

    parser = _TextExtractor()
    try:
        parser.feed(value)
        text = "".join(parser.parts)
    except Exception:
        text = re.sub(r"<[^>]+>", " ", value)

    text = html.unescape(text)
    text = text.replace("\u00a0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n", text)
    return text.strip()


def invoke(action: str, **params: Any) -> Any:
    payload = json.dumps({"action": action, "version": API_VERSION, "params": params}).encode("utf-8")
    req = urllib.request.Request(
        ANKICONNECT_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError(
            "Could not reach AnkiConnect. Make sure Anki Desktop is open and the AnkiConnect add-on is installed."
        ) from exc

    if not isinstance(body, dict) or "error" not in body or "result" not in body:
        raise RuntimeError(f"Unexpected AnkiConnect response for {action!r}: {body!r}")
    if body["error"]:
        raise RuntimeError(f"AnkiConnect error during {action}: {body['error']}")
    return body["result"]


def chunks(values: List[int], size: int = 500) -> Iterable[List[int]]:
    for i in range(0, len(values), size):
        yield values[i : i + size]


def ordered_fields(fields: Dict[str, Dict[str, Any]]) -> List[Dict[str, str]]:
    ordered = sorted(fields.items(), key=lambda item: item[1].get("order", 9999))
    return [
        {
            "name": name,
            "value": str(meta.get("value", "")),
        }
        for name, meta in ordered
    ]


def export_deck(deck_name: str) -> Dict[str, Any]:
    # Quoted deck search safely handles spaces and nested deck names.
    escaped = deck_name.replace("\\", "\\\\").replace('"', '\\"')
    note_ids: List[int] = invoke("findNotes", query=f'deck:"{escaped}"')
    notes: List[Dict[str, Any]] = []

    for batch in chunks(note_ids):
        info = invoke("notesInfo", notes=batch)
        for note in info:
            notes.append(
                {
                    "id": str(note["noteId"]),
                    "cardIDs": [str(card) for card in note.get("cards", [])],
                    "noteType": note.get("modelName", ""),
                    "tags": note.get("tags", []),
                    "fields": ordered_fields(note.get("fields", {})),
                }
            )

    # Stable order gives deterministic widget rotation between exports.
    notes.sort(key=lambda n: n["id"])
    return {"name": deck_name, "notes": notes, "count": len(notes)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Export Anki decks to JSON for 成为流 → 快学.")
    parser.add_argument("--deck", action="append", default=[], help="Exact deck name. Repeat for multiple decks.")
    parser.add_argument("--all", action="store_true", help="Export all decks returned by AnkiConnect.")
    parser.add_argument("--list-decks", action="store_true", help="Print available deck names and exit.")
    parser.add_argument("-o", "--output", default="anki-widget.json", help="Output JSON path.")
    args = parser.parse_args()

    try:
        all_decks: List[str] = invoke("deckNames")

        if args.list_decks:
            for name in all_decks:
                print(name)
            return 0

        selected = list(dict.fromkeys(all_decks if args.all else args.deck))
        if not selected:
            parser.error("Choose at least one --deck, or use --all / --list-decks.")

        missing = [name for name in selected if name not in all_decks]
        if missing:
            raise RuntimeError("Deck(s) not found: " + ", ".join(missing))

        profile = invoke("getActiveProfile")
        exported = [export_deck(name) for name in selected]
        if invoke("getActiveProfile") != profile:
            raise RuntimeError("Anki profile changed during export. Export again.")
        payload = {
            "schemaVersion": 2,
            "sourceProfile": profile,
            "exportedAt": datetime.now(timezone.utc).isoformat(),
            "source": "Anki Desktop via AnkiConnect",
            "decks": exported,
        }

        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(output.name + ".tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        temporary.replace(output)

        total = sum(deck["count"] for deck in exported)
        print(f"Exported {total} notes from {len(exported)} deck(s) -> {output}")
        print("Transfer this file to your iPhone, then import it from 成为流 → 快学.")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
