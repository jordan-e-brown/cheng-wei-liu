import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from anki_activity_import import Bridge, load_events
from anki_widget_export import export_deck, ordered_fields


def event(**changes):
    e = dict(id="event-1", deviceID="phone-1", timestamp="2026-09-06T12:00:00.123Z", type="review", source="app", noteID="101", cardID="201", deckName="中文", sourceProfile="User 1", rating=3, elapsedMilliseconds=1000)
    e.update(changes)
    return e


class FakeAnki:
    def __init__(self):
        self.calls = []
        self.answer_count = 0
        self.lose_response = False
        self.profile = "User 1"
        self.card_note = 101
        self.queue = 2

    def __call__(self, action, **params):
        self.calls.append((action, params))
        if action == "getActiveProfile": return self.profile
        if action == "notesInfo": return [dict(noteId=101)]
        if action == "findNotes": return [101]
        if action == "addTags": return None
        if action == "cardsInfo": return [dict(cardId=201, note=self.card_note, queue=self.queue)]
        if action == "answerCards":
            self.answer_count += 1
            if self.lose_response: raise TimeoutError("response lost AFTER Anki applied review")
            return [True]
        raise AssertionError(action)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "journal.sqlite3"
        self.anki = FakeAnki()
        self.bridge = Bridge(self.path, "User 1", self.anki)

    def tearDown(self):
        self.bridge.close()
        self.temp.cleanup()

    def test_duplicate_review_and_restart(self):
        self.assertEqual(self.bridge.process(event(), True), "review_applied")
        self.bridge.close()
        self.bridge = Bridge(self.path, "User 1", self.anki)
        self.assertEqual(self.bridge.process(event(), True), "already_applied")
        self.assertEqual(self.anki.answer_count, 1)

    def test_lost_response_never_automatically_replays(self):
        self.anki.lose_response = True
        with self.assertRaises(TimeoutError): self.bridge.process(event(), True)
        self.anki.lose_response = False
        with self.assertRaisesRegex(ValueError, "uncertain"): self.bridge.process(event(), True)
        self.assertEqual(self.anki.answer_count, 1)
        self.bridge.resolve("event-1", "applied")
        self.assertEqual(self.bridge.process(event(), True), "already_applied")

    def test_uncertain_review_blocks_later_ratings(self):
        self.anki.lose_response = True
        with self.assertRaises(TimeoutError): self.bridge.process(event(), True)
        self.anki.lose_response = False
        with self.assertRaisesRegex(ValueError, "uncertain review"):
            self.bridge.process(event(id="later", timestamp="2026-09-06T12:01:00Z"), True)
        self.assertEqual(self.anki.answer_count, 1)

    def test_older_export_cannot_grade_after_newer_review(self):
        self.bridge.process(event(), True)
        with self.assertRaisesRegex(ValueError, "newer review"):
            self.bridge.process(event(id="older", timestamp="2026-09-05T12:00:00Z"), True)
        self.assertEqual(self.anki.answer_count, 1)

    def test_changed_payload_same_id_rejected(self):
        self.bridge.process(event(), True)
        with self.assertRaisesRegex(ValueError, "different payload"): self.bridge.process(event(rating=1), True)
        self.assertEqual(self.anki.answer_count, 1)

    def test_activity_only_can_later_upgrade_to_review(self):
        self.assertEqual(self.bridge.process(event()), "activity_saved")
        self.assertEqual(self.anki.answer_count, 0)
        self.assertEqual(self.bridge.process(event(), True), "review_applied")
        self.assertEqual(self.anki.answer_count, 1)

    def test_missing_card_or_profile_is_practice_only(self):
        self.assertEqual(self.bridge.process(event(cardID=None), True), "practice_only")
        self.assertEqual(self.bridge.process(event(id="e2", sourceProfile=None), True), "practice_only")
        self.assertEqual(self.anki.answer_count, 0)

    def test_guid_maps_to_note_without_inventing_card(self):
        self.assertEqual(self.bridge.process(event(noteID="guid:abc", noteGUID="abc", cardID=None, sourceProfile=None), True), "practice_only")
        self.assertIn(("findNotes", {"query": 'guid:"abc"'}), self.anki.calls)

    def test_wrong_profile_and_card_mapping_blocked(self):
        self.anki.profile = "Other"
        with self.assertRaises(ValueError): self.bridge.process(event(), True)
        self.anki.profile = "User 1"
        self.anki.card_note = 999
        with self.assertRaisesRegex(ValueError, "belongs"): self.bridge.process(event(), True)
        self.assertEqual(self.anki.answer_count, 0)

    def test_suspended_card_never_graded(self):
        self.anki.queue = -1
        with self.assertRaisesRegex(ValueError, "suspended"): self.bridge.process(event(), True)
        self.assertEqual(self.anki.answer_count, 0)

    def test_batch_validation_and_dedup(self):
        path = Path(self.temp.name) / "activity.json"
        path.write_text(json.dumps(dict(schemaVersion=1, events=[event(), event()])))
        self.assertEqual(len(load_events(path)), 1)
        for bad in [event(rating=True), event(timestamp="2026-09-06"), event(cardID="bad"), event(elapsedMilliseconds=-1), event(source="unknown")]:
            path.write_text(json.dumps(dict(schemaVersion=1, events=[bad])))
            with self.assertRaises(ValueError): load_events(path)

    def test_conflicting_events_rejected_before_any_apply(self):
        path = Path(self.temp.name) / "activity.json"
        path.write_text(json.dumps(dict(schemaVersion=1, events=[event(), event(rating=1)])))
        with self.assertRaises(ValueError): load_events(path)
        self.assertEqual(self.anki.calls, [])

    def test_exporter_preserves_fields_and_card_ids(self):
        fields = {"English": {"value": "<b>hello</b>", "order": 1}, "Hanzi": {"value": "你好", "order": 0}}
        self.assertEqual(ordered_fields(fields)[1]["value"], "<b>hello</b>")
        def call(action, **params):
            if action == "findNotes": return [101]
            if action == "notesInfo": return [dict(noteId=101, cards=[201, 202], fields=fields)]
            raise AssertionError(action)
        with patch("anki_widget_export.invoke", call): payload = export_deck("中文")
        self.assertEqual(payload["notes"][0]["cardIDs"], ["201", "202"])
        self.assertEqual(payload["notes"][0]["fields"][0]["name"], "Hanzi")


if __name__ == "__main__": unittest.main()
