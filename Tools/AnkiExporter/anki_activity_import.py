#!/usr/bin/env python3
"""Validate/export iOS activity into Anki via AnkiConnect, with a durable journal.

Dry-run by default. --apply adds activity tags. --apply --apply-reviews also
submits eligible ratings at sync time (not historical revlog/FSRS reconstruction).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from anki_widget_export import invoke

KINDS = {"opened", "revealed", "skipped", "review"}


def load_events(path: Path) -> list[dict[str, Any]]:
    if path.stat().st_size > 100 * 1024 * 1024:
        raise ValueError("Activity file exceeds 100 MB")
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict) or payload.get("schemaVersion") != 1 or not isinstance(payload.get("events"), list):
        raise ValueError("Expected activity schemaVersion 1 with events[]")
    seen = {}
    for e in payload["events"]:
        if not isinstance(e, dict):
            raise ValueError("Each event must be an object")
        for key in ("id", "deviceID", "timestamp", "type", "source", "noteID", "deckName"):
            if not isinstance(e.get(key), str) or not e[key].strip():
                raise ValueError(f"Missing/invalid event {key}")
        if e["type"] not in KINDS or e["source"] not in {"app", "widget"}:
            raise ValueError(f"Unknown event type/source: {e['id']}")
        instant = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00"))
        if instant.tzinfo is None:
            raise ValueError("Event timestamps must include a timezone")
        if e["type"] == "review" and (type(e.get("rating")) is not int or e["rating"] not in range(1, 5)):
            raise ValueError("Review rating must be 1–4")
        for key in ("cardID", "noteGUID", "sourceProfile"):
            if e.get(key) is not None and (not isinstance(e[key], str) or not e[key]):
                raise ValueError(f"Invalid {key}")
        if e.get("cardID") and (not e["cardID"].isdigit() or int(e["cardID"]) <= 0):
            raise ValueError("Invalid cardID")
        if e.get("elapsedMilliseconds") is not None and (type(e["elapsedMilliseconds"]) is not int or e["elapsedMilliseconds"] < 0):
            raise ValueError("Invalid elapsedMilliseconds")
        if e["id"] in seen and seen[e["id"]] != e:
            raise ValueError(f"Conflicting payloads for event {e['id']}")
        seen[e["id"]] = e
    return sorted(seen.values(), key=lambda e: (datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")), e["id"]))


def quote_search(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


class Bridge:
    def __init__(self, journal: Path, profile: str, call=invoke):
        self.profile, self.call = profile, call
        journal.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(journal, timeout=30)
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS events (
            profile TEXT NOT NULL, id TEXT NOT NULL, digest TEXT NOT NULL,
            payload TEXT NOT NULL, tagged INTEGER NOT NULL DEFAULT 0,
            review_state TEXT NOT NULL DEFAULT 'pending', PRIMARY KEY(profile, id))""")
        self.db.commit()

    def close(self):
        self.db.close()

    def require_profile(self):
        if self.call("getActiveProfile") != self.profile:
            raise ValueError(f"Open Anki profile {self.profile!r} before applying this export")

    def resolve_note(self, event):
        if event["noteID"].isdigit() and int(event["noteID"]) > 0:
            ids = [int(event["noteID"])]
        elif event.get("noteGUID"):
            ids = self.call("findNotes", query="guid:" + quote_search(event["noteGUID"]))
        else:
            raise ValueError("No Anki note ID or GUID (sample notes cannot sync)")
        if len(ids) != 1:
            raise ValueError("Note missing or GUID mapping is ambiguous")
        info = self.call("notesInfo", notes=ids)
        if len(info) != 1 or info[0].get("noteId") != ids[0]:
            raise ValueError("Note no longer exists in Anki")
        # Require the exported deck/subdeck as an additional guard for profile-local IDs.
        matching = self.call("findNotes", query="nid:" + str(ids[0]) + " deck:" + quote_search(event["deckName"]))
        if ids[0] not in matching:
            raise ValueError("Note is no longer in the exported deck; reconcile before syncing")
        return ids[0]

    def process(self, event, apply_reviews=False):
        self.require_profile()
        if event.get("sourceProfile") and event["sourceProfile"] != self.profile:
            raise ValueError("Export came from a different Anki profile")
        payload = json.dumps(event, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        digest = hashlib.sha256(payload.encode()).hexdigest()
        # Serialize simultaneous bridge processes; a crash releases SQLite's lock.
        self.db.execute("BEGIN IMMEDIATE")
        row = self.db.execute("SELECT digest,tagged,review_state FROM events WHERE profile=? AND id=?", (self.profile, event["id"])).fetchone()
        if row and row[0] != digest:
            self.db.rollback()
            raise ValueError("Event ID was already used with a different payload")
        if not row:
            self.db.execute("INSERT INTO events(profile,id,digest,payload) VALUES (?,?,?,?)", (self.profile, event["id"], digest, payload))
        self.db.commit()
        note_id = self.resolve_note(event)
        # addTags is idempotent. Retrying after a crash cannot duplicate a review.
        self.require_profile()
        self.call("addTags", notes=[note_id], tags="chengweiliu::" + event["type"])
        with self.db:
            self.db.execute("UPDATE events SET tagged=1 WHERE profile=? AND id=?", (self.profile, event["id"]))
        if event["type"] != "review" or not apply_reviews:
            return "activity_saved"
        if not event.get("cardID") or not event.get("sourceProfile"):
            return "practice_only"
        self.db.execute("BEGIN IMMEDIATE")
        state = self.db.execute("SELECT review_state FROM events WHERE profile=? AND id=?", (self.profile, event["id"])).fetchone()[0]
        if state == "applied":
            self.db.commit()
            return "already_applied"
        if state == "in_flight":
            self.db.commit()
            raise ValueError("Review outcome is uncertain. Reconcile it in Anki before using --resolve-review; automatic replay is blocked")
        try:
            unresolved = self.db.execute("SELECT id FROM events WHERE profile=? AND review_state='in_flight'", (self.profile,)).fetchone()
            if unresolved:
                raise ValueError(f"Reconcile uncertain review {unresolved[0]} before applying later ratings")
            applied = self.db.execute("SELECT payload FROM events WHERE profile=? AND review_state='applied'", (self.profile,)).fetchall()
            instant = datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00"))
            for (prior_payload,) in applied:
                prior = json.loads(prior_payload)
                if prior.get("cardID") == event["cardID"] and datetime.fromisoformat(prior["timestamp"].replace("Z", "+00:00")) > instant:
                    raise ValueError("A newer review for this card was already applied; reconcile this older event")
            cards = self.call("cardsInfo", cards=[int(event["cardID"])])
            if len(cards) != 1 or cards[0].get("cardId") != int(event["cardID"]) or cards[0].get("note") != note_id:
                raise ValueError("Card ID no longer belongs to the exported note")
            if cards[0].get("queue", -1) < 0:
                raise ValueError("Card is suspended or buried; review was not applied")
            self.require_profile()
            self.db.execute("UPDATE events SET review_state='in_flight' WHERE profile=? AND id=?", (self.profile, event["id"]))
            self.db.commit()  # Persist BEFORE the non-idempotent remote call.
        except Exception:
            self.db.rollback()
            raise
        result = self.call("answerCards", answers=[{"cardId": int(event["cardID"]), "ease": event["rating"]}])
        if result != [True]:
            raise ValueError("Anki did not confirm this review; reconcile its in_flight journal entry")
        with self.db:
            self.db.execute("UPDATE events SET review_state='applied' WHERE profile=? AND id=?", (self.profile, event["id"]))
        return "review_applied"

    def resolve(self, event_id, resolution):
        with self.db:
            cursor = self.db.execute("UPDATE events SET review_state=? WHERE profile=? AND id=? AND review_state='in_flight'", ("applied" if resolution == "applied" else "pending", self.profile, event_id))
        if cursor.rowcount != 1:
            raise ValueError("No in_flight event found for this profile and event ID")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input", nargs="?", type=Path)
    p.add_argument("--profile", required=True, help="Exact Anki profile receiving this activity")
    p.add_argument("--journal", type=Path, default=Path.home() / ".chengweiliu" / "activity.sqlite3")
    p.add_argument("--apply", action="store_true", help="Archive events and add activity tags to Anki")
    p.add_argument("--apply-reviews", action="store_true", help="Also submit eligible ratings to Anki at sync time")
    p.add_argument("--receipt", type=Path, help="Write per-event outcomes to this JSON file")
    p.add_argument("--resolve-review", metavar="EVENT_ID")
    p.add_argument("--resolution", choices=["applied", "retry"])
    args = p.parse_args()
    try:
        if args.resolve_review:
            if not args.resolution or not args.apply:
                p.error("Manual reconciliation needs --apply --resolution applied|retry")
            bridge = Bridge(args.journal, args.profile)
            try: bridge.resolve(args.resolve_review, args.resolution)
            finally: bridge.close()
            print("Journal updated after manual reconciliation.")
            return 0
        if not args.input:
            p.error("Provide an activity JSON file")
        events = load_events(args.input)
        if args.apply_reviews and not args.apply:
            p.error("--apply-reviews requires --apply")
        if not args.apply:
            print(f"Validated {len(events)} unique events. No changes made. Use --apply to archive and tag, and optionally --apply-reviews to grade at sync time.")
            return 0
        bridge = Bridge(args.journal, args.profile)
        outcomes = []
        try:
            bridge.require_profile()
            for event in events:
                try:
                    outcome = {"id": event["id"], "status": bridge.process(event, args.apply_reviews)}
                except Exception as exc:
                    outcome = {"id": event["id"], "status": "failed", "error": str(exc)}
                outcomes.append(outcome)
        finally:
            bridge.close()
        report = {"schemaVersion": 1, "profile": args.profile, "processedAt": datetime.now(timezone.utc).isoformat(), "outcomes": outcomes}
        if args.receipt:
            args.receipt.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1 if any(o["status"] == "failed" for o in outcomes) else 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
