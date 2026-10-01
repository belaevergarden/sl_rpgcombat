"""Semantics of the LSL subset interpreter, checked before the game scripts."""

import hashlib
import unittest

from lslvm import Script, plain


def call(source, name, *args):
    script = Script(source + "\ndefault { state_entry() {} }\n")
    return plain(script.call(name, *args))


class TestArithmetic(unittest.TestCase):
    def test_integer_division_truncates_toward_zero(self):
        source = """
            integer quot() { return -7 / 2; }
            integer rem() { return 5 % 3; }
            integer wrap() { return 2147483647 + 2; }
        """
        self.assertEqual(call(source, "quot"), -3)
        self.assertEqual(call(source, "rem"), 2)
        self.assertEqual(call(source, "wrap"), -2147483647)

    def test_casts(self):
        source = """
            integer num(string text) { return (integer)text; }
            string show(integer value) { return (string)value; }
            integer flag(string text) { return text == "1"; }
        """
        self.assertEqual(call(source, "num", "12abc"), 12)
        self.assertEqual(call(source, "num", "-4x"), -4)
        self.assertEqual(call(source, "num", "xyz"), 0)
        self.assertEqual(call(source, "num", " 3"), 0)
        self.assertEqual(call(source, "show", -1859789070), "-1859789070")
        self.assertEqual(call(source, "flag", "1"), 1)


class TestStringsAndLists(unittest.TestCase):
    def test_substring_indexes(self):
        source = """
            string mid(string text, integer a, integer b) { return llGetSubString(text, a, b); }
            string cut(string text, integer a, integer b) { return llDeleteSubString(text, a, b); }
        """
        self.assertEqual(call(source, "mid", "Hello!", 0, 0), "H")
        self.assertEqual(call(source, "mid", "Hello!", -1, -1), "!")
        self.assertEqual(call(source, "mid", "Hello!", 2, 3), "ll")
        self.assertEqual(call(source, "mid", "abcd", 0, -1), "abcd")
        self.assertEqual(call(source, "mid", "abcd", 1, -2), "bc")
        self.assertEqual(call(source, "mid", "abcd", -2, -1), "cd")
        self.assertEqual(call(source, "cut", "gen_batata", 0, 3), "batata")

    def test_parse_and_sha1(self):
        source = """
            list keep(string text) { return llParseStringKeepNulls(text, [","], []); }
            list drop(string text) { return llParseString2List(text, [","], []); }
            string sha(string text) { return llSHA1String(text); }
            integer find(string hay, string needle) { return llSubStringIndex(hay, needle); }
        """
        self.assertEqual(call(source, "keep", "a,,b"), ["a", "", "b"])
        self.assertEqual(call(source, "drop", "a,,b"), ["a", "b"])
        self.assertEqual(call(source, "keep", ""), [""])
        self.assertEqual(call(source, "drop", ""), [])
        self.assertEqual(call(source, "keep", "a,"), ["a", ""])
        digest = hashlib.sha1(b"abc").hexdigest()
        self.assertEqual(call(source, "sha", "abc"), digest)
        self.assertEqual(call(source, "find", "hp=30", "="), 2)
        self.assertEqual(call(source, "find", "hp", "="), -1)

    def test_list_search_is_type_sensitive(self):
        source = """
            integer by_key(string text) {
                return llListFindList([text], [(key)text]);
            }
            integer by_text(string text) {
                return llListFindList([text], [text]);
            }
        """
        avatar = "22222222-2222-4222-8222-222222222222"
        self.assertEqual(call(source, "by_text", avatar), 0)
        self.assertEqual(call(source, "by_key", avatar), -1)


class TestControl(unittest.TestCase):
    def test_short_circuit_and_loop(self):
        source = """
            integer hits;
            integer left() { hits = hits + 1; return 0; }
            integer right() { hits = hits + 1; return 1; }
            integer gate() {
                hits = 0;
                if (left() && right()) return hits;
                return hits;
            }
            integer sum(integer n) {
                integer i;
                integer total;
                for (i = 1; i <= n; i += 1) total = total + i;
                return total;
            }
        """
        self.assertEqual(call(source, "gate"), 1)
        self.assertEqual(call(source, "sum", 4), 10)


if __name__ == "__main__":
    unittest.main()
