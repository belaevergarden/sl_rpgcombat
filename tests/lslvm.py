"""A small interpreter for the LSL subset used by SL RPG Combat.

Second Life is not available here. This module loads the real `.lsl` sources,
runs their functions and events, and replaces `ll*` builtins with recordable
stand-ins. It is not a Second Life runtime: there is no viewer, no region, and
no real listener. Dice come from `script.frand_queue` (each value is a raw
`llFrand` result). When the queue is empty, `llFrand` returns 0.0. Time comes
from `script.time`.
"""

from __future__ import annotations

import hashlib
import math
import os
import re
import uuid
from collections import namedtuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

NULL_UUID = "00000000-0000-0000-0000-000000000000"
_UUID = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
_TYPES = {"integer", "float", "string", "key", "list", "vector", "rotation"}
_TWO = ["==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "<<", ">>", "++", "--"]
_EXPR_START = {"ident", "num", "str"}
_EXPR_OPS = {"(", "[", "<", "!", "~", "-", "+"}

Token = namedtuple("Token", "kind value line")
EOF = Token("eof", "", -1)


class LSLError(Exception):
    pass


class Key:
    def __init__(self, value):
        self.value = str(value).lower()

    def __repr__(self):
        return "key:" + self.value


class Vec:
    def __init__(self, x, y, z):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)

    def __repr__(self):
        return f"<{self.x}, {self.y}, {self.z}>"


NULL_KEY = Key(NULL_UUID)
ZERO_VECTOR = Vec(0.0, 0.0, 0.0)


def i32(number):
    number = int(number) & 0xFFFFFFFF
    if number >= 0x80000000:
        number -= 0x100000000
    return number


def plain(value):
    """Turn a VM value into plain Python for assertions."""
    if isinstance(value, Key):
        return value.value
    if isinstance(value, Vec):
        return (value.x, value.y, value.z)
    if isinstance(value, list):
        return [plain(item) for item in value]
    return value


def load_notecards(directory):
    names = sorted(
        name
        for name in os.listdir(directory)
        if not name.startswith(".")
        and os.path.isfile(os.path.join(directory, name))
    )
    texts = {}
    for name in names:
        with open(os.path.join(directory, name), encoding="utf-8") as handle:
            texts[name] = handle.read()
    return texts, names


def slice_ranges(length, start, end):
    """Inclusive LSL slice ranges. A start past end is an exclusion range."""
    if length <= 0:
        return []
    if start < 0:
        start = length + start
    if end < 0:
        end = length + end

    def clip(left, right):
        if right < 0 or left >= length:
            return None
        if left < 0:
            left = 0
        if right >= length:
            right = length - 1
        if left > right:
            return None
        return (left, right)

    if start <= end:
        span = clip(start, end)
        return [] if span is None else [span]
    if end < 0:
        span = clip(start, length - 1)
        return [] if span is None else [span]
    if end >= length:
        span = clip(0, end)
        return [] if span is None else [span]
    spans = []
    head = clip(0, end)
    tail = clip(start, length - 1)
    if head is not None:
        spans.append(head)
    if tail is not None:
        spans.append(tail)
    return spans


def _take(items, spans):
    out = []
    for left, right in spans:
        out.extend(items[left : right + 1])
    return out


def _drop(items, spans):
    gone = set()
    for left, right in spans:
        gone.update(range(left, right + 1))
    return [item for index, item in enumerate(items) if index not in gone]


class _Return(Exception):
    def __init__(self, value):
        self.value = value


class _Reset(Exception):
    pass


class Func:
    def __init__(self, name, ret, params, body, line):
        self.name = name
        self.ret = ret
        self.params = params
        self.body = body
        self.line = line


class Parser:
    def __init__(self, source, filename):
        self.filename = filename
        self.lines = source.splitlines() or [""]
        self.tokens = lex(source)
        self.pos = 0

    def parse(self):
        globals_ = []
        functions = []
        while not self._eof():
            if self._check_ident("default"):
                functions.extend(self._parse_default())
                break
            if self._is_type(self._peek()) and self._looks_like_function():
                functions.append(self._parse_function())
            elif self._is_type(self._peek()):
                globals_.append(self._parse_global())
            elif self._peek().kind == "ident" and self._ahead(1).value == "(":
                functions.append(self._parse_function())
            else:
                self._fail("expected a global, a function, or default")
        if not self._eof():
            self._fail("code after default")
        return globals_, functions

    def _parse_default(self):
        self._advance()
        self._expect_op("{")
        events = []
        while not self._check_op("}") and not self._eof():
            events.append(self._parse_function())
        self._expect_op("}")
        return events

    def _parse_global(self):
        line = self._peek().line
        type_name = self._advance().value
        name = self._expect_ident()
        init = None
        if self._match_op("="):
            init = self._parse_expr()
        self._expect_op(";")
        return ("global", line, type_name, name, init)

    def _parse_function(self):
        line = self._peek().line
        ret = None
        if self._is_type(self._peek()):
            ret = self._advance().value
        name = self._expect_ident()
        self._expect_op("(")
        params = []
        if not self._check_op(")"):
            while True:
                if not self._is_type(self._peek()):
                    self._fail("expected a parameter type")
                param_type = self._advance().value
                param_name = self._expect_ident()
                params.append((param_type, param_name))
                if not self._match_op(","):
                    break
        self._expect_op(")")
        body = self._parse_block()
        return Func(name, ret, params, body, line)

    def _parse_block(self):
        line = self._peek().line
        self._expect_op("{")
        statements = []
        while not self._check_op("}") and not self._eof():
            statements.append(self._parse_stmt())
        self._expect_op("}")
        return ("block", line, statements)

    def _parse_stmt(self):
        if self._check_op("{"):
            return self._parse_block()
        if self._check_ident("if"):
            return self._parse_if()
        if self._check_ident("while"):
            return self._parse_while()
        if self._check_ident("for"):
            return self._parse_for()
        if self._check_ident("return"):
            line = self._advance().line
            if self._match_op(";"):
                return ("return", line, None)
            expr = self._parse_expr()
            self._expect_op(";")
            return ("return", line, expr)
        if self._is_type(self._peek()) and self._ahead(1).kind == "ident":
            line = self._peek().line
            type_name = self._advance().value
            name = self._expect_ident()
            init = None
            if self._match_op("="):
                init = self._parse_expr()
            self._expect_op(";")
            return ("decl", line, type_name, name, init)
        line = self._peek().line
        expr = self._parse_expr()
        self._expect_op(";")
        return ("expr", line, expr)

    def _parse_if(self):
        line = self._advance().line
        self._expect_op("(")
        cond = self._parse_expr()
        self._expect_op(")")
        then = self._parse_stmt()
        other = None
        if self._match_ident("else"):
            other = self._parse_stmt()
        return ("if", line, cond, then, other)

    def _parse_while(self):
        line = self._advance().line
        self._expect_op("(")
        cond = self._parse_expr()
        self._expect_op(")")
        return ("while", line, cond, self._parse_stmt())

    def _parse_for(self):
        line = self._advance().line
        self._expect_op("(")
        init = None if self._check_op(";") else self._parse_expr()
        self._expect_op(";")
        cond = None if self._check_op(";") else self._parse_expr()
        self._expect_op(";")
        step = None if self._check_op(")") else self._parse_expr()
        self._expect_op(")")
        return ("for", line, init, cond, step, self._parse_stmt())

    def _parse_expr(self):
        left = self._parse_or()
        op = self._peek_op()
        if op in ("=", "+="):
            if left[0] != "name":
                self._fail("assignment target must be a name")
            self._advance()
            return ("assign", left[1], op, self._parse_expr())
        return left

    def _parse_or(self):
        left = self._parse_and()
        while self._match_op("||"):
            left = ("binary", "||", left, self._parse_and())
        return left

    def _parse_and(self):
        left = self._parse_bor()
        while self._match_op("&&"):
            left = ("binary", "&&", left, self._parse_bor())
        return left

    def _parse_bor(self):
        left = self._parse_bxor()
        while self._match_op("|"):
            left = ("binary", "|", left, self._parse_bxor())
        return left

    def _parse_bxor(self):
        left = self._parse_band()
        while self._match_op("^"):
            left = ("binary", "^", left, self._parse_band())
        return left

    def _parse_band(self):
        left = self._parse_eq()
        while self._match_op("&"):
            left = ("binary", "&", left, self._parse_eq())
        return left

    def _parse_eq(self):
        left = self._parse_rel()
        while self._peek_op() in ("==", "!="):
            op = self._advance().value
            left = ("binary", op, left, self._parse_rel())
        return left

    def _parse_rel(self):
        left = self._parse_shift()
        while True:
            op = self._peek_op()
            if op in ("<", "<=", ">="):
                self._advance()
                left = ("binary", op, left, self._parse_shift())
                continue
            if op == ">":
                nxt = self._ahead(1)
                if not _can_start(nxt):
                    break
                self._advance()
                left = ("binary", op, left, self._parse_shift())
                continue
            break
        return left

    def _parse_shift(self):
        left = self._parse_add()
        while self._peek_op() in ("<<", ">>"):
            op = self._advance().value
            left = ("binary", op, left, self._parse_add())
        return left

    def _parse_add(self):
        left = self._parse_mul()
        while self._peek_op() in ("+", "-"):
            op = self._advance().value
            left = ("binary", op, left, self._parse_mul())
        return left

    def _parse_mul(self):
        left = self._parse_unary()
        while self._peek_op() in ("*", "/", "%"):
            op = self._advance().value
            left = ("binary", op, left, self._parse_unary())
        return left

    def _parse_unary(self):
        if self._check_op("(") and self._is_type(self._ahead(1)) and self._ahead(2).value == ")":
            self._advance()
            type_name = self._advance().value
            self._advance()
            return ("cast", type_name, self._parse_unary())
        if self._check_op("("):
            self._advance()
            expr = self._parse_expr()
            self._expect_op(")")
            return expr
        if self._peek_op() in ("!", "~", "-", "+"):
            op = self._advance().value
            return ("unary", op, self._parse_unary())
        return self._parse_postfix()

    def _parse_postfix(self):
        expr = self._parse_primary()
        while self._check_op("("):
            if expr[0] != "name":
                self._fail("only a name can be called")
            self._advance()
            args = []
            if not self._check_op(")"):
                args.append(self._parse_expr())
                while self._match_op(","):
                    args.append(self._parse_expr())
            self._expect_op(")")
            expr = ("call", expr[1], args)
        return expr

    def _parse_primary(self):
        tok = self._peek()
        if tok.kind == "num":
            self._advance()
            return ("num", tok.value)
        if tok.kind == "str":
            self._advance()
            return ("str", tok.value)
        if tok.kind == "ident":
            self._advance()
            return ("name", tok.value)
        if self._match_op("["):
            items = []
            if not self._check_op("]"):
                items.append(self._parse_expr())
                while self._match_op(","):
                    items.append(self._parse_expr())
            self._expect_op("]")
            return ("list", items)
        if self._match_op("<"):
            x = self._parse_expr()
            self._expect_op(",")
            y = self._parse_expr()
            self._expect_op(",")
            z = self._parse_expr()
            self._expect_op(">")
            return ("vec", x, y, z)
        self._fail("expected an expression")

    def _looks_like_function(self):
        return self._ahead(1).kind == "ident" and self._ahead(2).value == "("

    def _is_type(self, tok):
        return tok.kind == "ident" and tok.value in _TYPES

    def _peek(self):
        if self.pos >= len(self.tokens):
            return EOF
        return self.tokens[self.pos]

    def _ahead(self, offset):
        index = self.pos + offset
        if index >= len(self.tokens):
            return EOF
        return self.tokens[index]

    def _eof(self):
        return self._peek().kind == "eof"

    def _peek_op(self):
        tok = self._peek()
        if tok.kind == "op":
            return tok.value
        return ""

    def _check_op(self, value):
        return self._peek_op() == value

    def _check_ident(self, value):
        tok = self._peek()
        return tok.kind == "ident" and tok.value == value

    def _match_op(self, value):
        if self._check_op(value):
            self._advance()
            return True
        return False

    def _match_ident(self, value):
        if self._check_ident(value):
            self._advance()
            return True
        return False

    def _advance(self):
        tok = self._peek()
        if tok.kind == "eof":
            self._fail("unexpected end of script")
        self.pos += 1
        return tok

    def _expect_op(self, value):
        if not self._match_op(value):
            self._fail(f"expected {value}")

    def _expect_ident(self):
        tok = self._peek()
        if tok.kind != "ident":
            self._fail("expected a name")
        self._advance()
        return tok.value

    def _fail(self, message):
        tok = self._peek()
        line = tok.line
        source = ""
        if 1 <= line <= len(self.lines):
            source = "\n" + self.lines[line - 1]
        raise LSLError(f"{self.filename}:{line}: {message}{source}")


def _can_start(tok):
    if tok.kind in _EXPR_START:
        return True
    return tok.kind == "op" and tok.value in _EXPR_OPS


def lex(source):
    tokens = []
    i = 0
    line = 1
    n = len(source)
    while i < n:
        ch = source[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        if ch in " \t\r":
            i += 1
            continue
        if ch == "/" and i + 1 < n and source[i + 1] == "/":
            i += 2
            while i < n and source[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and source[i + 1] == "*":
            i += 2
            while i + 1 < n and not (source[i] == "*" and source[i + 1] == "/"):
                if source[i] == "\n":
                    line += 1
                i += 1
            i = min(n, i + 2)
            continue
        if ch == '"':
            i += 1
            buf = []
            while i < n and source[i] != '"':
                if source[i] == "\\":
                    i += 1
                    if i >= n:
                        break
                    esc = source[i]
                    buf.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"'}.get(esc, esc))
                    i += 1
                    continue
                if source[i] == "\n":
                    line += 1
                buf.append(source[i])
                i += 1
            i += 1
            tokens.append(Token("str", "".join(buf), line))
            continue
        if ch.isdigit() or (ch == "." and i + 1 < n and source[i + 1].isdigit()):
            match = re.match(r"\d+\.\d*|\.\d+", source[i:])
            if match:
                tokens.append(Token("num", float(match.group(0)), line))
                i += len(match.group(0))
                continue
            match = re.match(r"\d+", source[i:])
            tokens.append(Token("num", int(match.group(0)), line))
            i += len(match.group(0))
            continue
        if ch.isalpha() or ch == "_":
            match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", source[i:])
            tokens.append(Token("ident", match.group(0), line))
            i += len(match.group(0))
            continue
        for op in _TWO:
            if source.startswith(op, i):
                tokens.append(Token("op", op, line))
                i += len(op)
                break
        else:
            tokens.append(Token("op", ch, line))
            i += 1
    return tokens


class Script:
    def __init__(self, source, filename="<script>"):
        self.filename = filename
        globals_, functions = Parser(source, filename).parse()
        self.functions = {}
        for func in functions:
            if func.name in self.functions:
                raise LSLError(f"duplicate function {func.name}")
            self.functions[func.name] = func
        self.types = {}
        self.values = {}
        self.linkset = {}
        self.notecard_lines = {}
        self.inventory = []
        self.pending = []
        self.frand_queue = []
        self.frand_used = 0
        self.time = 0
        self.key = Key(NULL_UUID)
        self.owner = Key(NULL_UUID)
        self.object_name = "Object"
        self.position = Vec(0.0, 0.0, 0.0)
        self.positions = {}
        self.avatars = set()
        self.owners = {}
        self.profiles = {}
        self.user_keys = {}
        self.detected = []
        self.owner_says = []
        self.says = []
        self.region_says = []
        self.links = []
        self.dialogs = []
        self.textboxes = []
        self.sensors = []
        self.hovers = []
        self.listens = []
        self.timer = 0.0
        self.listen_serial = 0
        self.did_reset = False
        self.scopes = []
        self.stack = []
        self.line = 1
        self._seed_constants()
        for kind, line, type_name, name, init in globals_:
            self.line = line
            if init is None:
                value = self.default(type_name)
            else:
                value = self.cast(type_name, self.eval(init))
            self.types[name] = type_name
            self.values[name] = value
        self._bind_builtins()

    @classmethod
    def load(cls, path):
        with open(path, encoding="utf-8") as handle:
            return cls(handle.read(), filename=path)

    def use_notecards(self, texts, order=None):
        self.notecard_lines = {name: text.splitlines() for name, text in texts.items()}
        self.inventory = list(order) if order is not None else list(texts)

    def get(self, name):
        return self.values[name]

    def set(self, name, value):
        if name not in self.types:
            raise LSLError(f"unknown global {name}")
        self.values[name] = self.cast(self.types[name], self.import_value(value))

    def call(self, name, *args):
        try:
            return self._invoke(name, [self.import_value(arg) for arg in args])
        except _Reset:
            self.did_reset = True
            return None

    def deliver(self, limit=10000):
        steps = 0
        while self.pending and steps < limit and not self.did_reset:
            kind, query, *rest = self.pending.pop(0)
            if kind == "nc":
                name, line = rest
                lines = self.notecard_lines.get(name, [])
                if line < 0 or line >= len(lines):
                    data = self.values["EOF"]
                else:
                    data = lines[line]
            else:
                found = self.user_keys.get(str(rest[0]).lower())
                data = NULL_UUID if found is None else found
            self.call("dataserver", query, data)
            steps += 1
        if self.pending and not self.did_reset:
            raise LSLError("notecard delivery did not finish")
        return steps

    def clear_io(self):
        self.owner_says.clear()
        self.says.clear()
        self.region_says.clear()
        self.links.clear()
        self.dialogs.clear()
        self.textboxes.clear()
        self.sensors.clear()
        self.hovers.clear()

    def default(self, type_name):
        if type_name == "integer":
            return 0
        if type_name == "float":
            return 0.0
        if type_name == "string":
            return ""
        if type_name == "key":
            return NULL_KEY
        if type_name == "list":
            return []
        if type_name == "vector":
            return ZERO_VECTOR
        raise LSLError(f"unsupported type {type_name}")

    def import_value(self, value):
        if isinstance(value, (Key, Vec)):
            return value
        if isinstance(value, bool):
            return 1 if value else 0
        if isinstance(value, int):
            return i32(value)
        if isinstance(value, float):
            return float(value)
        if isinstance(value, str):
            return value
        if isinstance(value, list):
            return [self.import_value(item) for item in value]
        if (
            isinstance(value, tuple)
            and len(value) == 3
            and all(isinstance(item, (int, float)) for item in value)
        ):
            return Vec(*value)
        raise LSLError(f"cannot import {type(value).__name__}")

    def cast(self, type_name, value):
        if type_name == "integer":
            return self.as_int(value)
        if type_name == "float":
            return self.as_float(value)
        if type_name == "string":
            return self.as_str(value)
        if type_name == "key":
            return self.as_key(value)
        if type_name == "list":
            if not isinstance(value, list):
                raise LSLError("expected a list")
            return list(value)
        if type_name == "vector":
            if not isinstance(value, Vec):
                raise LSLError("expected a vector")
            return value
        raise LSLError(f"unsupported type {type_name}")

    def as_int(self, value):
        if isinstance(value, bool):
            return 1 if value else 0
        if isinstance(value, int):
            return i32(value)
        if isinstance(value, float):
            return i32(math.trunc(value))
        if isinstance(value, str):
            return _int_from_string(value)
        if isinstance(value, Key):
            return 0
        raise LSLError(f"cannot cast {type(value).__name__} to integer near line {self.line}")

    def as_float(self, value):
        if isinstance(value, bool):
            return 1.0 if value else 0.0
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            return _float_from_string(value)
        raise LSLError(f"cannot cast {type(value).__name__} to float near line {self.line}")

    def as_str(self, value):
        if isinstance(value, str):
            return value
        if isinstance(value, bool):
            return "1" if value else "0"
        if isinstance(value, int):
            return str(i32(value))
        if isinstance(value, float):
            return f"{value:.6f}"
        if isinstance(value, Key):
            return value.value
        if isinstance(value, Vec):
            return f"<{value.x:.5f}, {value.y:.5f}, {value.z:.5f}>"
        raise LSLError(f"cannot cast {type(value).__name__} to string near line {self.line}")

    def as_key(self, value):
        if isinstance(value, Key):
            return value
        text = value if isinstance(value, str) else self.as_str(value)
        if _UUID.match(text):
            return Key(text)
        return NULL_KEY

    def _seed_constants(self):
        pairs = {
            "TRUE": ("integer", 1),
            "FALSE": ("integer", 0),
            "NULL_KEY": ("key", NULL_KEY),
            "EOF": ("string", "\n\n\n"),
            "PI": ("float", math.pi),
            "STRING_TRIM": ("integer", 3),
            "ZERO_VECTOR": ("vector", ZERO_VECTOR),
            "LINK_SET": ("integer", -1),
            "OBJECT_POS": ("integer", 3),
            "INVENTORY_NOTECARD": ("integer", 7),
            "INVENTORY_NONE": ("integer", -1),
            "CHANGED_INVENTORY": ("integer", 1),
            "CHANGED_OWNER": ("integer", 128),
            "AGENT": ("integer", 1),
        }
        for name, (type_name, value) in pairs.items():
            self.types[name] = type_name
            self.values[name] = value

    def _bind_builtins(self):
        self._builtins = {
            "llSHA1String": self.b_sha1,
            "llGetUnixTime": self.b_time,
            "llFrand": self.b_frand,
            "llOwnerSay": self.b_owner_say,
            "llSay": self.b_say,
            "llRegionSayTo": self.b_region_say,
            "llMessageLinked": self.b_message_linked,
            "llDialog": self.b_dialog,
            "llTextBox": self.b_textbox,
            "llSetText": self.b_set_text,
            "llSetTimerEvent": self.b_timer,
            "llListen": self.b_listen,
            "llListenRemove": self.b_listen_remove,
            "llResetScript": self.b_reset,
            "llGetInventoryType": self.b_inventory_type,
            "llGetInventoryNumber": self.b_inventory_number,
            "llGetInventoryName": self.b_inventory_name,
            "llGetNotecardLine": self.b_notecard_line,
            "llRequestUserKey": self.b_user_key,
            "llGetOwner": self.b_owner,
            "llGetKey": self.b_key,
            "llGetOwnerKey": self.b_owner_key,
            "llGetDisplayName": self.b_display_name,
            "llGetUsername": self.b_username,
            "llKey2Name": self.b_key2name,
            "llGetAgentSize": self.b_agent_size,
            "llGetObjectDetails": self.b_object_details,
            "llVecDist": self.b_vec_dist,
            "llGetPos": self.b_pos,
            "llGetObjectName": self.b_get_object_name,
            "llSetObjectName": self.b_set_object_name,
            "llStringLength": self.b_string_length,
            "llGetSubString": self.b_substring,
            "llDeleteSubString": self.b_delete_substring,
            "llSubStringIndex": self.b_substring_index,
            "llParseString2List": self.b_parse2,
            "llParseStringKeepNulls": self.b_parse_keep,
            "llDumpList2String": self.b_dump,
            "llStringTrim": self.b_trim,
            "llToLower": self.b_lower,
            "llToUpper": self.b_upper,
            "llList2Integer": self.b_list_int,
            "llList2String": self.b_list_str,
            "llList2Key": self.b_list_key,
            "llList2Vector": self.b_list_vec,
            "llGetListLength": self.b_list_len,
            "llList2List": self.b_list_slice,
            "llDeleteSubList": self.b_list_delete,
            "llListFindList": self.b_list_find,
            "llListReplaceList": self.b_list_replace,
            "llLinksetDataRead": self.b_ls_read,
            "llLinksetDataWrite": self.b_ls_write,
            "llLinksetDataDelete": self.b_ls_delete,
            "llSensor": self.b_sensor,
            "llDetectedKey": self.b_detected_key,
        }

    def _invoke(self, name, args):
        func = self.functions.get(name)
        if func is None:
            if name not in self._builtins:
                raise LSLError(
                    f"{self.filename}:{self.line}: unimplemented {name} while calling {self.stack}"
                )
            return self._builtins[name](args)
        if len(args) != len(func.params):
            raise LSLError(f"{name} expected {len(func.params)} arguments, got {len(args)}")
        if len(self.stack) > 200:
            raise LSLError("script recursion is too deep")
        scope = {}
        for (type_name, param_name), arg in zip(func.params, args):
            scope[param_name] = (type_name, self.cast(type_name, arg))
        self.stack.append(name)
        self.scopes.append(scope)
        try:
            try:
                self.exec_stmt(func.body)
            except _Return as returned:
                value = returned.value
            else:
                value = None
        finally:
            self.scopes.pop()
            self.stack.pop()
        if func.ret is None:
            return None
        if value is None:
            return self.default(func.ret)
        return self.cast(func.ret, value)

    def exec_stmt(self, stmt):
        kind = stmt[0]
        self.line = stmt[1]
        if kind == "block":
            self.scopes.append({})
            try:
                for child in stmt[2]:
                    self.exec_stmt(child)
            finally:
                self.scopes.pop()
        elif kind == "decl":
            _, _, type_name, name, init = stmt
            value = self.default(type_name) if init is None else self.cast(type_name, self.eval(init))
            self.scopes[-1][name] = (type_name, value)
        elif kind == "expr":
            self.eval(stmt[2])
        elif kind == "return":
            value = None if stmt[2] is None else self.eval(stmt[2])
            raise _Return(value)
        elif kind == "if":
            if self.truthy(self.eval(stmt[2])):
                self.exec_stmt(stmt[3])
            elif stmt[4] is not None:
                self.exec_stmt(stmt[4])
        elif kind == "while":
            spins = 0
            while self.truthy(self.eval(stmt[2])):
                spins += 1
                if spins > 100000:
                    raise LSLError(f"while loop ran too long near line {self.line}")
                self.exec_stmt(stmt[3])
        elif kind == "for":
            _, _, init, cond, step, body = stmt
            if init is not None:
                self.eval(init)
            spins = 0
            while cond is None or self.truthy(self.eval(cond)):
                spins += 1
                if spins > 100000:
                    raise LSLError(f"for loop ran too long near line {self.line}")
                self.exec_stmt(body)
                if step is not None:
                    self.eval(step)
                if cond is None and step is None and init is None:
                    raise LSLError("refusing an empty infinite for loop")
        else:
            raise LSLError(f"unknown statement {kind}")

    def eval(self, node):
        kind = node[0]
        if kind == "num" or kind == "str":
            return node[1]
        if kind == "name":
            return self.lookup(node[1])
        if kind == "assign":
            _, name, op, expr = node
            if op == "=":
                value = self.eval(expr)
            elif op == "+=":
                value = self.apply_op("+", self.lookup(name), self.eval(expr))
            else:
                raise LSLError(f"unsupported assignment {op}")
            self.store(name, value)
            return value
        if kind == "unary":
            return self.apply_unary(node[1], self.eval(node[2]))
        if kind == "cast":
            return self.cast(node[1], self.eval(node[2]))
        if kind == "binary":
            op = node[1]
            if op == "&&":
                if not self.truthy(self.eval(node[2])):
                    return 0
                return 1 if self.truthy(self.eval(node[3])) else 0
            if op == "||":
                if self.truthy(self.eval(node[2])):
                    return 1
                return 1 if self.truthy(self.eval(node[3])) else 0
            return self.apply_op(op, self.eval(node[2]), self.eval(node[3]))
        if kind == "call":
            args = [self.eval(arg) for arg in node[2]]
            return self._invoke(node[1], args)
        if kind == "list":
            return [self.eval(item) for item in node[1]]
        if kind == "vec":
            return Vec(
                self.as_float(self.eval(node[1])),
                self.as_float(self.eval(node[2])),
                self.as_float(self.eval(node[3])),
            )
        raise LSLError(f"unknown expression {kind}")

    def lookup(self, name):
        for scope in reversed(self.scopes):
            if name in scope:
                return scope[name][1]
        if name in self.values:
            return self.values[name]
        raise LSLError(f"{self.filename}:{self.line}: unknown name {name} in {self.stack}")

    def store(self, name, value):
        for scope in reversed(self.scopes):
            if name in scope:
                type_name = scope[name][0]
                scope[name] = (type_name, self.cast(type_name, value))
                return
        if name not in self.values:
            raise LSLError(f"{self.filename}:{self.line}: unknown name {name}")
        self.values[name] = self.cast(self.types[name], value)

    def truthy(self, value):
        if isinstance(value, bool):
            return value
        if isinstance(value, int):
            return value != 0
        if isinstance(value, float):
            return value != 0.0
        if isinstance(value, str):
            return value != ""
        if isinstance(value, Key):
            return value.value != NULL_UUID
        if isinstance(value, list):
            return len(value) != 0
        if isinstance(value, Vec):
            return not (value.x == 0.0 and value.y == 0.0 and value.z == 0.0)
        return False

    def apply_unary(self, op, value):
        if op == "!":
            return 0 if self.truthy(value) else 1
        if op == "-":
            if isinstance(value, float):
                return -value
            return i32(-self.as_int(value))
        if op == "+":
            if isinstance(value, float):
                return value
            return self.as_int(value)
        if op == "~":
            return i32(~self.as_int(value))
        raise LSLError(f"unsupported unary {op}")

    def apply_op(self, op, left, right):
        if op == "+":
            if isinstance(left, list) or isinstance(right, list):
                if not isinstance(left, list) or not isinstance(right, list):
                    raise LSLError("list addition needs two lists")
                return list(left) + list(right)
            if isinstance(left, str) or isinstance(right, str):
                if not isinstance(left, str) or not isinstance(right, str):
                    raise LSLError(
                        f"string addition needs two strings ({type(left).__name__}, {type(right).__name__}) near line {self.line}"
                    )
                return left + right
            if isinstance(left, float) or isinstance(right, float):
                return self.as_float(left) + self.as_float(right)
            if isinstance(left, Vec) and isinstance(right, Vec):
                return Vec(left.x + right.x, left.y + right.y, left.z + right.z)
            return i32(self.as_int(left) + self.as_int(right))
        if op == "-":
            if isinstance(left, float) or isinstance(right, float):
                return self.as_float(left) - self.as_float(right)
            if isinstance(left, Vec) and isinstance(right, Vec):
                return Vec(left.x - right.x, left.y - right.y, left.z - right.z)
            return i32(self.as_int(left) - self.as_int(right))
        if op == "*":
            if isinstance(left, float) or isinstance(right, float):
                return self.as_float(left) * self.as_float(right)
            return i32(self.as_int(left) * self.as_int(right))
        if op == "/":
            if isinstance(left, float) or isinstance(right, float):
                denom = self.as_float(right)
                if denom == 0.0:
                    raise LSLError("division by zero")
                return self.as_float(left) / denom
            return i32(_div_trunc(self.as_int(left), self.as_int(right)))
        if op == "%":
            return i32(_mod_trunc(self.as_int(left), self.as_int(right)))
        if op in ("<", "<=", ">", ">="):
            return 1 if _compare(op, left, right) else 0
        if op == "==":
            return 1 if self.values_equal(left, right) else 0
        if op == "!=":
            return 0 if self.values_equal(left, right) else 1
        if op == "&":
            return i32(self.as_int(left) & self.as_int(right))
        if op == "|":
            return i32(self.as_int(left) | self.as_int(right))
        if op == "^":
            return i32(self.as_int(left) ^ self.as_int(right))
        if op == "<<":
            return i32(self.as_int(left) << (self.as_int(right) & 31))
        if op == ">>":
            return i32(self.as_int(left) >> (self.as_int(right) & 31))
        raise LSLError(f"unsupported operator {op}")

    def values_equal(self, left, right):
        if _is_num(left) and _is_num(right):
            if isinstance(left, float) or isinstance(right, float):
                return float(left) == float(right)
            return int(left) == int(right)
        if _is_text(left) and _is_text(right):
            return _text(left) == _text(right)
        if isinstance(left, Vec) and isinstance(right, Vec):
            return left.x == right.x and left.y == right.y and left.z == right.z
        if isinstance(left, list) and isinstance(right, list):
            return len(left) == len(right) and all(
                self.values_equal(a, b) for a, b in zip(left, right)
            )
        return False

    def same_item(self, left, right):
        if type(left) is not type(right):
            return False
        if type(left) is float or type(left) is int:
            return left == right
        if type(left) is str:
            return left == right
        if type(left) is Key:
            return left.value == right.value
        if type(left) is Vec:
            return left.x == right.x and left.y == right.y and left.z == right.z
        if type(left) is list:
            return len(left) == len(right) and all(
                self.same_item(a, b) for a, b in zip(left, right)
            )
        return False

    def _list_at(self, items, index):
        if not isinstance(items, list):
            raise LSLError("expected a list")
        index = self.as_int(index)
        if index < 0:
            index += len(items)
        if index < 0 or index >= len(items):
            return None
        return items[index]

    def _profile(self, value, field):
        key = self.as_key(value)
        return self.profiles.get(key.value, {}).get(field, "")

    def _pos_of(self, value):
        key = self.as_key(value)
        if key.value == self.key.value:
            return self.position
        return self.positions.get(key.value)

    def b_sha1(self, args):
        return hashlib.sha1(self.as_str(args[0]).encode("utf-8")).hexdigest()

    def b_time(self, args):
        return i32(self.time)

    def b_frand(self, args):
        self.frand_used += 1
        if self.frand_queue:
            return float(self.frand_queue.pop(0))
        return 0.0

    def b_owner_say(self, args):
        self.owner_says.append(self.as_str(args[0]))
        return None

    def b_say(self, args):
        self.says.append(
            {
                "channel": self.as_int(args[0]),
                "text": self.as_str(args[1]),
                "name": self.object_name,
            }
        )
        return None

    def b_region_say(self, args):
        self.region_says.append(
            (self.as_key(args[0]), self.as_int(args[1]), self.as_str(args[2]))
        )
        return None

    def b_message_linked(self, args):
        self.links.append(
            (self.as_int(args[0]), self.as_int(args[1]), self.as_str(args[2]), self.as_key(args[3]))
        )
        return None

    def b_dialog(self, args):
        labels = args[2] if isinstance(args[2], list) else []
        self.dialogs.append(
            (self.as_key(args[0]), self.as_str(args[1]), [self.as_str(item) for item in labels], self.as_int(args[3]))
        )
        return None

    def b_textbox(self, args):
        self.textboxes.append((self.as_key(args[0]), self.as_str(args[1]), self.as_int(args[2])))
        return None

    def b_set_text(self, args):
        self.hovers.append((self.as_str(args[0]), args[1], self.as_float(args[2])))
        return None

    def b_timer(self, args):
        self.timer = self.as_float(args[0])
        return None

    def b_listen(self, args):
        self.listen_serial += 1
        self.listens.append(self.listen_serial)
        return self.listen_serial

    def b_listen_remove(self, args):
        return None

    def b_reset(self, args):
        self.did_reset = True
        raise _Reset()

    def b_inventory_type(self, args):
        name = self.as_str(args[0])
        if name in self.notecard_lines:
            return self.values["INVENTORY_NOTECARD"]
        return self.values["INVENTORY_NONE"]

    def b_inventory_number(self, args):
        if self.as_int(args[0]) == self.values["INVENTORY_NOTECARD"]:
            return len(self.inventory)
        return 0

    def b_inventory_name(self, args):
        if self.as_int(args[0]) != self.values["INVENTORY_NOTECARD"]:
            return ""
        index = self.as_int(args[1])
        if index < 0 or index >= len(self.inventory):
            return ""
        return self.inventory[index]

    def b_notecard_line(self, args):
        query = Key(str(uuid.uuid4()))
        self.pending.append(("nc", query, self.as_str(args[0]), self.as_int(args[1])))
        return query

    def b_user_key(self, args):
        query = Key(str(uuid.uuid4()))
        self.pending.append(("uk", query, self.as_str(args[0])))
        return query

    def b_owner(self, args):
        return self.owner

    def b_key(self, args):
        return self.key

    def b_owner_key(self, args):
        key = self.as_key(args[0])
        if key.value in self.owners:
            return self.owners[key.value]
        if key.value in self.avatars:
            return key
        return NULL_KEY

    def b_display_name(self, args):
        return self._profile(args[0], "display")

    def b_username(self, args):
        return self._profile(args[0], "user")

    def b_key2name(self, args):
        return self._profile(args[0], "legacy")

    def b_agent_size(self, args):
        key = self.as_key(args[0])
        if key.value in self.avatars:
            return Vec(0.45, 0.6, 1.8)
        return ZERO_VECTOR

    def b_object_details(self, args):
        pos = self._pos_of(args[0])
        if pos is None:
            return []
        params = args[1] if isinstance(args[1], list) else []
        out = []
        for flag in params:
            if self.as_int(flag) == self.values["OBJECT_POS"]:
                out.append(pos)
            else:
                out.append(0)
        return out

    def b_vec_dist(self, args):
        a = args[0]
        b = args[1]
        if not isinstance(a, Vec) or not isinstance(b, Vec):
            raise LSLError("llVecDist expected vectors")
        return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2)

    def b_pos(self, args):
        return self.position

    def b_get_object_name(self, args):
        return self.object_name

    def b_set_object_name(self, args):
        self.object_name = self.as_str(args[0])
        return None

    def b_string_length(self, args):
        return len(self.as_str(args[0]))

    def b_substring(self, args):
        text = self.as_str(args[0])
        parts = _take(list(text), slice_ranges(len(text), self.as_int(args[1]), self.as_int(args[2])))
        return "".join(parts)

    def b_delete_substring(self, args):
        text = self.as_str(args[0])
        parts = _drop(list(text), slice_ranges(len(text), self.as_int(args[1]), self.as_int(args[2])))
        return "".join(parts)

    def b_substring_index(self, args):
        return self.as_str(args[0]).find(self.as_str(args[1]))

    def b_parse2(self, args):
        return _parse_pieces(self.as_str(args[0]), args[1], args[2], False)

    def b_parse_keep(self, args):
        return _parse_pieces(self.as_str(args[0]), args[1], args[2], True)

    def b_dump(self, args):
        items = args[0] if isinstance(args[0], list) else []
        return self.as_str(args[1]).join(self.as_str(item) for item in items)

    def b_trim(self, args):
        text = self.as_str(args[0])
        mode = self.as_int(args[1])
        space = " \t\n\r\v\f"
        if mode & 1:
            text = text.lstrip(space)
        if mode & 2:
            text = text.rstrip(space)
        return text

    def b_lower(self, args):
        return self.as_str(args[0]).lower()

    def b_upper(self, args):
        return self.as_str(args[0]).upper()

    def b_list_int(self, args):
        item = self._list_at(args[0], args[1])
        if item is None:
            return 0
        return self.as_int(item)

    def b_list_str(self, args):
        item = self._list_at(args[0], args[1])
        if item is None:
            return ""
        return self.as_str(item)

    def b_list_key(self, args):
        item = self._list_at(args[0], args[1])
        if item is None:
            return NULL_KEY
        return self.as_key(item)

    def b_list_vec(self, args):
        item = self._list_at(args[0], args[1])
        if isinstance(item, Vec):
            return item
        return ZERO_VECTOR

    def b_list_len(self, args):
        if not isinstance(args[0], list):
            raise LSLError("expected a list")
        return len(args[0])

    def b_list_slice(self, args):
        items = list(args[0])
        return _take(items, slice_ranges(len(items), self.as_int(args[1]), self.as_int(args[2])))

    def b_list_delete(self, args):
        items = list(args[0])
        return _drop(items, slice_ranges(len(items), self.as_int(args[1]), self.as_int(args[2])))

    def b_list_find(self, args):
        hay = args[0] if isinstance(args[0], list) else []
        needle = args[1] if isinstance(args[1], list) else []
        if not needle:
            return 0
        last = len(hay) - len(needle) + 1
        for index in range(last):
            if all(self.same_item(hay[index + offset], needle[offset]) for offset in range(len(needle))):
                return index
        return -1

    def b_list_replace(self, args):
        dest = list(args[0])
        src = list(args[1]) if isinstance(args[1], list) else []
        spans = slice_ranges(len(dest), self.as_int(args[2]), self.as_int(args[3]))
        if len(spans) != 1:
            raise LSLError("llListReplaceList exclusion range is not used by these scripts")
        left, right = spans[0]
        return dest[:left] + src + dest[right + 1 :]

    def b_ls_read(self, args):
        return self.linkset.get(self.as_str(args[0]), "")

    def b_ls_write(self, args):
        self.linkset[self.as_str(args[0])] = self.as_str(args[1])
        return 1

    def b_ls_delete(self, args):
        self.linkset.pop(self.as_str(args[0]), None)
        return 1

    def b_sensor(self, args):
        self.sensors.append(
            (
                self.as_str(args[0]),
                self.as_key(args[1]),
                self.as_int(args[2]),
                self.as_float(args[3]),
                self.as_float(args[4]),
            )
        )
        return None

    def b_detected_key(self, args):
        index = self.as_int(args[0])
        if index < 0 or index >= len(self.detected):
            return NULL_KEY
        return self.detected[index]


def _int_from_string(text):
    i = 0
    n = len(text)
    if i < n and text[i] in "+-":
        sign = -1 if text[i] == "-" else 1
        i += 1
    else:
        sign = 1
    if i >= n or not text[i].isdigit():
        return 0
    number = 0
    while i < n and text[i].isdigit():
        number = number * 10 + int(text[i])
        i += 1
    return i32(sign * number)


def _float_from_string(text):
    match = re.match(r"[+-]?\d+(?:\.\d*)?|\.\d+", text)
    if not match:
        return 0.0
    return float(match.group(0))


def _div_trunc(left, right):
    if right == 0:
        raise LSLError("division by zero")
    quot = abs(left) // abs(right)
    if (left < 0) ^ (right < 0):
        quot = -quot
    return quot


def _mod_trunc(left, right):
    if right == 0:
        raise LSLError("modulo by zero")
    return left - right * _div_trunc(left, right)


def _is_num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_text(value):
    return isinstance(value, (str, Key))


def _text(value):
    if isinstance(value, Key):
        return value.value
    return value


def _compare(op, left, right):
    if isinstance(left, str) and isinstance(right, str):
        pair = (left, right)
    elif _is_num(left) and _is_num(right):
        pair = (left, right)
    else:
        raise LSLError(f"cannot compare {type(left).__name__} {op} {type(right).__name__}")
    if op == "<":
        return pair[0] < pair[1]
    if op == "<=":
        return pair[0] <= pair[1]
    if op == ">":
        return pair[0] > pair[1]
    if op == ">=":
        return pair[0] >= pair[1]
    raise LSLError(op)


def _parse_pieces(src, seps, spacers, keep_nulls):
    sep_list = [item for item in seps if isinstance(item, str) and item != ""]
    spacer_list = [item for item in spacers if isinstance(item, str) and item != ""]
    spacer_set = set(spacer_list)
    keys = sorted(set(sep_list + spacer_list), key=len, reverse=True)
    parts = []
    buf = []
    i = 0
    n = len(src)
    while i < n:
        match = None
        for key in keys:
            if src.startswith(key, i):
                match = key
                break
        if match is None:
            buf.append(src[i])
            i += 1
            continue
        piece = "".join(buf)
        buf = []
        if piece or keep_nulls:
            parts.append(piece)
        if match in spacer_set:
            parts.append(match)
        i += len(match)
    piece = "".join(buf)
    if piece or keep_nulls:
        parts.append(piece)
    if not keep_nulls:
        parts = [part for part in parts if part != ""]
    return parts


if __name__ == "__main__":
    import glob

    for path in sorted(glob.glob(os.path.join(ROOT, "*", "scripts", "*.lsl"))):
        Script.load(path)
        print("parsed", os.path.relpath(path, ROOT))
