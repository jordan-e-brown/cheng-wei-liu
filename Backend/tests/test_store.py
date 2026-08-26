import tempfile
import unittest
from pathlib import Path

from app.store import ConversationStore, EMPTY_MEMORY


class ConversationStoreTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.store = ConversationStore(Path(self.tempdir.name) / "test.sqlite3")

    def tearDown(self):
        self.tempdir.cleanup()

    def test_exchange_round_trip_and_memory_reset(self):
        session_id = self.store.ensure_session(None, "你好")
        self.store.add_exchange(session_id, "你好", "你好！今天过得怎么样？")

        messages = self.store.get_messages(session_id)
        self.assertEqual([m["role"] for m in messages], ["user", "assistant"])
        self.assertEqual(messages[0]["content"], "你好")

        self.store.set_project_memory("Learner prefers natural Mandarin.")
        self.assertIn("natural Mandarin", self.store.get_project_memory())
        self.store.reset_project_memory()
        self.assertEqual(self.store.get_project_memory(), EMPTY_MEMORY)

    def test_existing_session_reopens(self):
        session_id = self.store.ensure_session(None, "第一次")
        self.store.close_session(session_id)
        reopened = self.store.ensure_session(session_id, "继续")
        self.assertEqual(reopened, session_id)


if __name__ == "__main__":
    unittest.main()
