import tempfile
import unittest
from pathlib import Path

from badminton_analysis.user_registry import (
    InvalidUserId,
    UserAlreadyExists,
    get_user,
    register_user,
)


class UserRegistryTest(unittest.TestCase):
    def test_register_user_rejects_duplicate_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "users.json"
            first = register_user(path, user_id="jiale_01")

            self.assertEqual(first["user_id"], "jiale_01")
            self.assertNotIn("nickname", first)
            with self.assertRaises(UserAlreadyExists):
                register_user(path, user_id="jiale_01")

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

    def test_existing_nickname_data_is_not_exposed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "users.json"
            path.write_text(
                """
                {
                  "schema_version": "user-registry-v1",
                  "users": {
                    "player01": {
                      "user_id": "player01",
                      "nickname": "Old",
                      "created_at": 1,
                      "updated_at": 2
                    }
                  }
                }
                """,
                encoding="utf-8",
            )

            user = get_user(path, "player01")

            self.assertEqual(user["user_id"], "player01")
            self.assertNotIn("nickname", user)


if __name__ == "__main__":
    unittest.main()
