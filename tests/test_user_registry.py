import tempfile
import unittest
from pathlib import Path

from badminton_analysis.user_registry import (
    InvalidUserId,
    UserAlreadyExists,
    get_user,
    register_user,
    update_user,
)


class UserRegistryTest(unittest.TestCase):
    def test_register_user_rejects_duplicate_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "users.json"
            first = register_user(path, user_id="jiale_01", nickname="Jiale")

            self.assertEqual(first["user_id"], "jiale_01")
            self.assertEqual(first["nickname"], "Jiale")
            with self.assertRaises(UserAlreadyExists):
                register_user(path, user_id="jiale_01", nickname="Other")

    def test_user_id_is_case_insensitive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "users.json"
            register_user(path, user_id="jiale")

            with self.assertRaises(UserAlreadyExists):
                register_user(path, user_id="JIALE")

    def test_invalid_user_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "users.json"

            for user_id in ["ab", "_jiale", "jia le", "jiale.01"]:
                with self.subTest(user_id=user_id):
                    with self.assertRaises(InvalidUserId):
                        register_user(path, user_id=user_id)

    def test_update_registered_user_nickname(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "users.json"
            register_user(path, user_id="player01", nickname="Old")

            updated = update_user(path, user_id="player01", nickname="New")

            self.assertEqual(updated["nickname"], "New")
            self.assertEqual(get_user(path, "player01")["nickname"], "New")


if __name__ == "__main__":
    unittest.main()
