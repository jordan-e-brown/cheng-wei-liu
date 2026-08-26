import unittest

from app.prompts import LANGUAGE_PARTNER_PROMPT


class PromptBoundaryTests(unittest.TestCase):
    def test_language_partner_is_separate_from_self_study(self):
        rendered = LANGUAGE_PARTNER_PROMPT.format(project_memory="none")
        self.assertIn("completely separate from Anki/self-study", rendered)
        self.assertIn("elicited self-repair", rendered)
        self.assertIn("Prefer Mandarin", rendered)
        self.assertIn("Always use 汉语", rendered)


if __name__ == "__main__":
    unittest.main()
