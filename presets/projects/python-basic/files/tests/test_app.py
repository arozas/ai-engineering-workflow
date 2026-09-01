from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from {{pythonPackage}} import greet


class GreetTests(unittest.TestCase):
    def test_greets_valid_name(self) -> None:
        self.assertEqual(greet("Alejandro"), "Hello, Alejandro!")

    def test_rejects_empty_name(self) -> None:
        with self.assertRaises(ValueError):
            greet("  ")


if __name__ == "__main__":
    unittest.main()
