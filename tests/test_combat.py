"""Run the real HUD, NPC, and auth scripts outside Second Life.

Dice are injected as raw llFrand results: 0.0 is a 1, and 19.0 on a d20 is a 20.
"""

import filecmp
import hashlib
import os
import unittest

from lslvm import LSLError, NULL_KEY, Key, Script, Vec, load_notecards, plain

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OWNER = "11111111-1111-4111-8111-111111111111"
PLAYER = "22222222-2222-4222-8222-222222222222"
HUD_OBJ = "33333333-3333-4333-8333-333333333333"
NPC_OBJ = "44444444-4444-4444-8444-444444444444"
OTHER = "55555555-5555-4555-8555-555555555555"
WHEN = 1_700_000_000


def path(*parts):
    return os.path.join(ROOT, *parts)


class Rig:
    """One prim: several scripts that share chat, linkset data, and dice.

    The first script is the one tests read when a name exists in more than one.
    state_entry, timer, changed, on_rez, and link_message run on every script.
    """

    _BROADCAST = ("state_entry", "timer", "changed", "on_rez", "link_message", "sensor", "no_sensor")
    _SHARED = (
        "linkset",
        "notecard_lines",
        "inventory",
        "positions",
        "avatars",
        "owners",
        "profiles",
        "user_keys",
        "owner_says",
        "says",
        "region_says",
        "links",
        "dialogs",
        "textboxes",
        "sensors",
        "hovers",
    )

    def __init__(self, paths):
        parts = [Script.load(item) for item in paths]
        object.__setattr__(self, "parts", parts)
        shared_queue = []
        for part in parts:
            part.frand_queue = shared_queue
            part.peers = [other for other in parts if other is not part]
        base = parts[0]
        for part in parts[1:]:
            for name in self._SHARED:
                setattr(part, name, getattr(base, name))

    @property
    def did_reset(self):
        return any(part.did_reset for part in self.parts)

    def __setattr__(self, name, value):
        if name == "frand_queue":
            for part in self.parts:
                part.frand_queue = value
            return
        if name in ("time", "owner", "key", "position", "object_name", "detected"):
            for part in self.parts:
                setattr(part, name, value)
            return
        if name in self._SHARED:
            for part in self.parts:
                setattr(part, name, value)
            return
        setattr(self.parts[0], name, value)

    def __getattr__(self, name):
        return getattr(self.parts[0], name)

    def get(self, name):
        for part in self.parts:
            if name in part.values:
                return part.get(name)
        raise LSLError(f"unknown global {name}")

    def set(self, name, value):
        for part in self.parts:
            if name in part.values:
                part.set(name, value)
                return
        raise LSLError(f"unknown global {name}")

    def call(self, name, *args):
        if name in self._BROADCAST:
            result = None
            found = False
            for part in self.parts:
                if name in part.functions:
                    found = True
                    result = part.call(name, *args)
            if not found:
                raise LSLError(f"unknown function {name}")
            return result
        for part in self.parts:
            if name in part.functions:
                return part.call(name, *args)
        raise LSLError(f"unknown function {name}")

    def deliver(self, limit=10000):
        steps = 0
        while steps < limit and not self.did_reset:
            part = next((item for item in self.parts if item.pending and not item.did_reset), None)
            if part is None:
                return steps
            steps += part.deliver(limit=1, strict=False)
        if any(item.pending and not item.did_reset for item in self.parts):
            raise LSLError("notecard delivery did not finish")
        return steps

    def clear_io(self):
        self.parts[0].clear_io()

    def use_notecards(self, texts, order=None):
        self.parts[0].use_notecards(texts, order)
        lines = self.parts[0].notecard_lines
        inventory = self.parts[0].inventory
        for part in self.parts[1:]:
            part.notecard_lines = lines
            part.inventory = inventory


def click(script, message, who=None):
    if who is None:
        who = script.owner
    script.call("listen", plain(script.get("gChan")), "", who, message)


def touch(script, who):
    script.detected = [who if isinstance(who, Key) else Key(who)]
    script.call("touch_start", 1)


def boot_hud(extra=None, deliver=True):
    hud = Rig(
        [
            path("player", "scripts", "sl_rpg_hud.lsl"),
            path("player", "scripts", "sl_rpg_hud_ui.lsl"),
            path("player", "scripts", "sl_rpg_hud_cards.lsl"),
        ]
    )
    hud.time = WHEN
    hud.owner = Key(OWNER)
    hud.key = Key(HUD_OBJ)
    hud.position = Vec(0, 0, 0)
    hud.profiles[OWNER] = {
        "display": "Isabela",
        "user": "isabela.evergarden",
        "legacy": "Isabela Evergarden",
    }
    texts, order = load_notecards(path("player", "notecards"))
    for name, text in (extra or {}).items():
        texts[name] = text
        if name not in order:
            order.append(name)
    hud.use_notecards(texts, order)
    hud.call("state_entry")
    if deliver:
        hud.deliver()
    return hud


def boot_npc(extra=None, deliver=True):
    npc = Rig(
        [
            path("npc", "scripts", "sl_rpg_npc.lsl"),
            path("npc", "scripts", "sl_rpg_npc_ui.lsl"),
            path("npc", "scripts", "sl_rpg_npc_fight.lsl"),
        ]
    )
    npc.time = WHEN
    npc.owner = Key(OWNER)
    npc.key = Key(NPC_OBJ)
    npc.object_name = "Crate"
    npc.position = Vec(0, 0, 0)
    npc.profiles[OWNER] = {
        "display": "Isabela",
        "user": "isabela.evergarden",
        "legacy": "Isabela Evergarden",
    }
    texts, order = load_notecards(path("npc", "notecards"))
    for name, text in (extra or {}).items():
        texts[name] = text
        if name not in order:
            order.append(name)
    npc.use_notecards(texts, order)
    npc.call("state_entry")
    if deliver:
        npc.deliver()
    return npc


def place(script, avatar, xyz):
    script.avatars.add(avatar)
    script.positions[avatar] = Vec(*xyz)


def engage(npc):
    touch(npc, npc.owner)
    click(npc, "Manage")
    click(npc, "ON")


def action(kind, req="hud", name="Hero", atk=8, defense=12, hp=125, maximum=125, defending=0, avatar=PLAYER):
    return f"ACTION|{avatar}|{kind}|{req}|{name}|{atk}|{defense}|{hp}|{maximum}|{defending}"


def recv(npc, body, speaker=HUD_OBJ):
    npc.call("link_message", 1, plain(npc.get("LINK_RECV")), body, speaker)


class TestAuth(unittest.TestCase):
    def setUp(self):
        self.sender = Script.load(path("player", "scripts", "sl_rpg_auth.lsl"))
        self.receiver = Script.load(path("npc", "scripts", "sl_rpg_auth.lsl"))
        self.sender.time = WHEN
        self.receiver.time = WHEN
        self.sender.key = Key(HUD_OBJ)
        self.receiver.key = Key(NPC_OBJ)
        self.sender.owner = Key(OWNER)
        self.receiver.owner = Key(OWNER)

    def test_auth_copies_are_the_same_file(self):
        same = filecmp.cmp(
            path("player", "scripts", "sl_rpg_auth.lsl"),
            path("npc", "scripts", "sl_rpg_auth.lsl"),
            shallow=False,
        )
        self.assertTrue(same)

    def test_mac_matches_sha1_of_the_script_constants(self):
        body, ts, nonce = "PING", "1700000000", "nonce-1"
        digest = plain(self.sender.call("macFor", body, ts, nonce))
        other = plain(self.receiver.call("macFor", body, ts, nonce))
        material = "|".join(
            [
                plain(self.sender.get("SEC_PASSWORD")),
                str(plain(self.sender.get("SEC_CHANNEL"))),
                plain(self.sender.get("SEC_BUILD")),
                str(plain(self.sender.get("SEC_VERSION"))),
                ts,
                nonce,
                body,
            ]
        )
        self.assertEqual(digest, other)
        self.assertEqual(digest, hashlib.sha1(material.encode("utf-8")).hexdigest())
        self.assertEqual(len(digest), 40)

    def wire(self, body="PING", when=WHEN):
        self.sender.time = when
        self.sender.clear_io()
        self.sender.frand_queue = [0.0]
        self.sender.call("doSend", self.receiver.key, body)
        self.assertEqual(len(self.sender.region_says), 1)
        target, channel, wire = self.sender.region_says[0]
        self.assertEqual(plain(target), NPC_OBJ)
        self.assertEqual(channel, plain(self.sender.get("SEC_CHANNEL")))
        self.assertNotEqual(channel, 0)
        return wire

    def listen(self, wire, when=WHEN, speaker=HUD_OBJ):
        self.receiver.time = when
        self.receiver.clear_io()
        self.receiver.call(
            "listen",
            plain(self.receiver.get("SEC_CHANNEL")),
            "",
            speaker,
            wire,
        )

    def test_round_trip_accepts_a_real_message(self):
        wire = self.wire("ACTION|ping")
        self.listen(wire)
        self.assertEqual(len(self.receiver.links), 1)
        link, num, body, speaker = self.receiver.links[0]
        self.assertEqual(link, plain(self.receiver.get("LINK_SET")))
        self.assertEqual(num, plain(self.receiver.get("LINK_RECV")))
        self.assertEqual(body, "ACTION|ping")
        self.assertEqual(plain(speaker), HUD_OBJ)

    def _fresh_receiver(self):
        receiver = Script.load(path("npc", "scripts", "sl_rpg_auth.lsl"))
        receiver.key = Key(NPC_OBJ)
        receiver.time = WHEN
        return receiver

    def test_rejects_tamper_build_and_version(self):
        wire = self.wire()
        lines = wire.split("\n")
        self.assertEqual(len(lines), 7)

        lines[5] = "PONG"
        self.listen("\n".join(lines))
        self.assertEqual(self.receiver.links, [])
        self.assertEqual(self.receiver.owner_says, ["Ignored an unauthenticated combat message."])

        self.receiver = self._fresh_receiver()
        built = self.wire().split("\n")
        built[2] = "fork-9"
        self.listen("\n".join(built))
        self.assertEqual(self.receiver.links, [])
        self.assertIn("fork-9", self.receiver.owner_says[0])
        self.assertIn("official-1", self.receiver.owner_says[0])

        self.receiver = self._fresh_receiver()
        versioned = self.wire().split("\n")
        versioned[1] = "2"
        self.listen("\n".join(versioned))
        self.assertEqual(
            self.receiver.owner_says,
            ["Ignored a message from a different SL RPG Combat version."],
        )

    def test_unauthenticated_warning_is_rate_limited(self):
        first = self.wire().split("\n")
        first[5] = "NOPE"
        self.listen("\n".join(first))
        self.assertEqual(len(self.receiver.owner_says), 1)

        again = self.wire(when=WHEN + 59).split("\n")
        again[5] = "NOPE"
        self.listen("\n".join(again), when=WHEN + 59)
        self.assertEqual(self.receiver.owner_says, [])

        later = self.wire(when=WHEN + 60).split("\n")
        later[5] = "NOPE"
        self.listen("\n".join(later), when=WHEN + 60)
        self.assertEqual(len(self.receiver.owner_says), 1)

    def test_skew_boundaries_are_silent(self):
        wire = self.wire()
        for delta in (26, -11):
            self.listen(wire, when=WHEN + delta)
            self.assertEqual(self.receiver.links, [])
            self.assertEqual(self.receiver.owner_says, [])
        for delta in (25, -10):
            self.receiver = Script.load(path("npc", "scripts", "sl_rpg_auth.lsl"))
            self.receiver.time = WHEN + delta
            self.receiver.key = Key(NPC_OBJ)
            self.listen(wire, when=WHEN + delta)
            self.assertEqual(len(self.receiver.links), 1)

    def test_replay_window_keeps_twenty_four_nonces(self):
        wires = [self.wire(f"M{i}") for i in range(24)]
        for wire in wires:
            self.listen(wire)
            self.assertEqual(len(self.receiver.links), 1)
        self.listen(wires[0])
        self.assertEqual(self.receiver.links, [])
        twenty_fifth = self.wire("M24")
        self.listen(twenty_fifth)
        self.assertEqual(len(self.receiver.links), 1)
        self.listen(wires[0])
        self.assertEqual(plain(self.receiver.links[0][2]), "M0")

    def test_drops_self_wrong_channel_and_a_bad_send(self):
        wire = self.wire()
        self.listen(wire, speaker=NPC_OBJ)
        self.assertEqual(self.receiver.links, [])
        self.receiver.call("listen", 0, "", HUD_OBJ, wire)
        self.assertEqual(self.receiver.links, [])

        self.sender.clear_io()
        self.sender.call("doSend", NULL_KEY, "PING")
        self.sender.call("doSend", self.receiver.key, "")
        self.sender.call("doSend", self.receiver.key, "has\nnewline")
        self.assertEqual(self.sender.region_says, [])

    def test_state_entry_and_listen_switch(self):
        self.receiver.call("state_entry")
        self.assertEqual(
            self.receiver.owner_says,
            ["SL RPG Combat network ready. Build official-1."],
        )
        self.assertEqual(plain(self.receiver.links[0][2]), "official-1")
        self.assertEqual(plain(self.receiver.get("gListenOn")), 1)
        self.receiver.call("link_message", 1, plain(self.receiver.get("LINK_LISTEN")), "0", NULL_KEY)
        self.assertEqual(plain(self.receiver.get("gListenOn")), 0)
        self.receiver.call("link_message", 1, plain(self.receiver.get("LINK_SEND")), "PING", self.sender.key)
        self.assertEqual(self.receiver.region_says[-1][2].split("\n")[5], "PING")

    def test_dialog_channel_cannot_hit_the_combat_channel(self):
        hud = boot_hud()
        touch(hud, hud.owner)
        channel = plain(hud.get("gChan"))
        secret = plain(self.sender.get("SEC_CHANNEL"))
        self.assertLess(channel, 0)
        self.assertNotEqual(channel, secret)
        hud.frand_queue = [999999999.0]
        touch(hud, hud.owner)
        highest = plain(hud.get("gChan"))
        self.assertLess(highest, 0)
        self.assertNotEqual(highest, secret)


class TestHud(unittest.TestCase):
    def test_notecards_build_a_knight_and_custom_names(self):
        hud = boot_hud(
            {
                "gen_batata": "hp=3\nattack=1\ndefense=1\n",
                "race_dark_elf": "name=Dark Elf\nhp=10\nattack=1\ndefense=1\n",
                "class_back": "name=Back\nhp=1\nattack=0\ndefense=0\n",
            }
        )
        self.assertIn("No character yet. Touch the HUD to create one.", hud.owner_says)
        self.assertNotIn("Attack range is capped at 10m.", hud.owner_says)
        self.assertEqual(plain(hud.get("gRangeM")), 10)
        self.assertIn("Batata", plain(hud.get("gGName")))
        self.assertIn("Dark Elf", plain(hud.get("gRName")))

        touch(hud, hud.owner)
        self.assertEqual(hud.dialogs[-1][2], ["Presets", "Custom", "Roll"])
        click(hud, "Presets")
        buttons = hud.dialogs[-1][2]
        self.assertIn("Batata", buttons)
        self.assertIn("Female", buttons)
        click(hud, "Female")
        self.assertIn("Dark Elf", hud.dialogs[-1][2])
        click(hud, "Human")
        labels = hud.dialogs[-1][2]
        self.assertIn("Knight", labels)
        self.assertIn("Back.", labels)
        self.assertIn("Back", labels)
        click(hud, "Knight")
        prompt = hud.dialogs[-1][1]
        self.assertIn("HP 125", prompt)
        self.assertIn("Attack 8", prompt)
        self.assertIn("Defense 12", prompt)
        click(hud, "Accept")

        self.assertEqual(plain(hud.get("gHP")), 125)
        self.assertEqual(plain(hud.get("gMax")), 125)
        self.assertEqual(plain(hud.get("gAtk")), 8)
        self.assertEqual(plain(hud.get("gDef")), 12)
        self.assertEqual(plain(hud.get("gGender")), "gen_female")
        self.assertEqual(plain(hud.get("gRace")), "race_human")
        self.assertEqual(plain(hud.get("gClass")), "class_knight")
        self.assertEqual(plain(hud.get("gGPretty")), "Female")
        self.assertEqual(plain(hud.get("gRPretty")), "Human")
        self.assertEqual(plain(hud.get("gCPretty")), "Knight")
        self.assertEqual(hud.linkset["c.ready"], "1")
        self.assertEqual(hud.linkset["c.hp"], "125")
        self.assertEqual(hud.linkset["c.atk"], "8")
        self.assertEqual(hud.linkset["c.def"], "12")
        self.assertEqual(hud.linkset["c.custom"], "0")
        joined = " ".join(hud.owner_says)
        self.assertIn("HP 125", joined)
        self.assertIn("Attack 8", joined)
        self.assertIn("Defense 12", joined)

    def test_custom_wizard_and_config_rename_stay_distinct(self):
        hud = boot_hud()
        touch(hud, hud.owner)
        click(hud, "Custom")
        click(hud, "Rook")
        click(hud, "Construct")
        click(hud, "Golem")
        click(hud, "Guard")
        click(hud, "0")
        self.assertIn("HP must be at least 1.", hud.owner_says)
        click(hud, "100001")
        self.assertIn("The limit is 100000.", hud.owner_says)
        click(hud, "40")
        click(hud, "3")
        click(hud, "4")
        self.assertEqual(plain(hud.get("gMax")), 40)
        self.assertEqual(plain(hud.get("gHP")), 40)
        self.assertEqual(plain(hud.get("gAtk")), 3)
        self.assertEqual(plain(hud.get("gDef")), 4)
        self.assertEqual(plain(hud.get("gCustom")), 1)
        self.assertEqual(plain(hud.get("gWizard")), 0)
        self.assertEqual(plain(hud.get("gGPretty")), "Construct")

        click(hud, "Config")
        click(hud, "Name")
        click(hud, "A|B\nC")
        self.assertEqual(plain(hud.get("gName")), "A B C")
        self.assertEqual(plain(hud.get("gCustom")), 1)
        self.assertEqual(plain(hud.get("gText")), 0)
        self.assertIn("Name set to A B C.", hud.owner_says)
        self.assertIn("Character configuration", hud.dialogs[-1][1])

    def test_menu_attack_roll_defend_and_timeout(self):
        hud = boot_hud()
        touch(hud, hud.owner)
        click(hud, "Presets")
        click(hud, "Female")
        click(hud, "Human")
        click(hud, "Knight")
        click(hud, "Accept")
        hud.clear_io()

        before = len(hud.dialogs)
        touch(hud, Key(PLAYER))
        self.assertEqual(len(hud.dialogs), before)

        touch(hud, hud.owner)
        click(hud, "Attack")
        self.assertIn("Select a target by clicking an NPC.", hud.owner_says)

        hud.set("gTarget", NPC_OBJ)
        hud.positions[NPC_OBJ] = Vec(11, 0, 0)
        click(hud, "Attack")
        self.assertIn("Target is out of range.", hud.owner_says)
        self.assertIn("Maximum attack range: 10m.", hud.owner_says)

        hud.positions[NPC_OBJ] = Vec(2, 0, 0)
        hud.clear_io()
        click(hud, "Attack")
        body = hud.links[-1][2]
        self.assertEqual(body, f"ACTION|{OWNER}|ATTACK|hud|Isabela|8|12|125|125|0")
        hud.time += 9
        hud.call("timer")
        self.assertEqual(
            hud.owner_says,
            [
                "The NPC did not respond.",
                "It may be off, or it may not belong to this combat network.",
            ],
        )

        hud.clear_io()
        click(hud, "Roll")
        hud.frand_queue = [19.0]
        click(hud, "1d20")
        self.assertEqual(hud.says[-1]["text"], "Isabela rolls 1d20 and gets 20.")

        hud.clear_io()
        touch(hud, hud.owner)
        click(hud, "Defend")
        self.assertIn("You raise your guard. Defense +2", hud.owner_says[-1])
        self.assertEqual(plain(hud.get("gDefending")), 1)

    def test_query_and_health_respect_owner_and_range(self):
        hud = boot_hud()
        touch(hud, hud.owner)
        click(hud, "Presets")
        click(hud, "Female")
        click(hud, "Human")
        click(hud, "Knight")
        click(hud, "Accept")
        hud.positions[NPC_OBJ] = Vec(2, 0, 0)
        hud.clear_io()

        far = f"QUERY|{OWNER}|ATTACK|req-1|Gob\rlin"
        hud.positions[NPC_OBJ] = Vec(11, 0, 0)
        hud.call("link_message", 1, plain(hud.get("LINK_RECV")), far, NPC_OBJ)
        self.assertEqual(plain(hud.get("gTarget")), NULL_KEY.value)
        self.assertEqual(hud.links, [])

        hud.positions[NPC_OBJ] = Vec(2, 0, 0)
        hud.call("link_message", 1, plain(hud.get("LINK_RECV")), far, NPC_OBJ)
        self.assertEqual(plain(hud.get("gTarget")), NPC_OBJ)
        self.assertEqual(plain(hud.get("gTargetName")), "Gob lin")
        self.assertIn("ACTION|", hud.links[-1][2])
        self.assertIn("|req-1|", hud.links[-1][2])

        hud.clear_io()
        forged = f"HPDELTA|{PLAYER}|-10"
        hud.call("link_message", 1, plain(hud.get("LINK_RECV")), forged, NPC_OBJ)
        self.assertEqual(plain(hud.get("gHP")), 125)

        hud.positions[NPC_OBJ] = Vec(16, 0, 0)
        hud.call("link_message", 1, plain(hud.get("LINK_RECV")), f"HPDELTA|{OWNER}|-10", NPC_OBJ)
        self.assertEqual(plain(hud.get("gHP")), 125)
        self.assertIn("Ignored a health change from out of range.", hud.owner_says)

        hud.positions[NPC_OBJ] = Vec(15, 0, 0)
        hud.clear_io()
        hud.call("link_message", 1, plain(hud.get("LINK_RECV")), f"HPDELTA|{OWNER}|-10", NPC_OBJ)
        self.assertEqual(plain(hud.get("gHP")), 115)
        hud.call("link_message", 1, plain(hud.get("LINK_RECV")), f"HPDELTA|{OWNER}|-999", NPC_OBJ)
        self.assertEqual(plain(hud.get("gHP")), 0)
        self.assertIn("You are at 0 HP.", hud.owner_says)

    def test_helpers_and_range_cap(self):
        hud = boot_hud()
        self.assertEqual(plain(hud.call("titleFromFile", "gen_batata", "gen_")), "Batata")
        self.assertEqual(plain(hud.call("titleFromFile", "race_dark_elf", "race_")), "Dark Elf")
        self.assertEqual(plain(hud.call("titleFromFile", "class_necromancer", "class_")), "Necromancer")
        self.assertEqual(plain(hud.call("titleFromFile", "gen_", "gen_")), "gen_")
        self.assertEqual(plain(hud.call("sanitize", "  a|b\nc\r ")), "a b c")
        self.assertEqual(len(plain(hud.call("sanitize", "x" * 50))), 40)
        self.assertEqual(plain(hud.call("fitButton", "Prev")), "Prev.")
        self.assertEqual(plain(hud.call("fitButton", "Back")), "Back.")
        self.assertEqual(plain(hud.call("fitButton", "")), " ")
        self.assertEqual(plain(hud.call("fitButton", "N" * 25)), "N" * 24)
        self.assertEqual(plain(hud.call("isUInt", " 12 ")), 1)
        self.assertEqual(plain(hud.call("isUInt", "12a")), 0)
        self.assertEqual(plain(hud.call("isUInt", "-1")), 0)
        self.assertEqual(plain(hud.call("isUInt", "")), 0)
        self.assertEqual(
            plain(hud.call("orderButtons", ["A", "B", "C", "D"])),
            ["D", " ", " ", "A", "B", "C"],
        )
        self.assertEqual(plain(hud.call("orderButtons", ["A", "B", "C"])), ["A", "B", "C"])
        self.assertEqual(plain(hud.call("orderButtons", ["A"])), ["A", " ", " "])
        self.assertEqual(
            plain(hud.call("orderButtons", ["A", "B", "C", "D", "E"])),
            ["D", "E", " ", "A", "B", "C"],
        )

        hud.set("gMode", 0)
        hud.clear_io()
        hud.call("parseLine", "range=50")
        self.assertEqual(plain(hud.get("gRangeM")), 10)
        self.assertEqual(hud.owner_says, ["Attack range is capped at 10m."])
        hud.call("parseLine", "# comment")
        hud.call("parseLine", "defend_bonus=4")
        self.assertEqual(plain(hud.get("gDefendBonus")), 4)

    def test_still_reading_and_owner_reset(self):
        hud = boot_hud(deliver=False)
        touch(hud, hud.owner)
        self.assertIn("The HUD is still reading configuration.", hud.owner_says)
        hud.linkset["c.name"] = "kept"
        hud.call("changed", plain(hud.get("CHANGED_OWNER")))
        self.assertTrue(hud.did_reset)
        self.assertNotIn("c.name", hud.linkset)


class TestNpc(unittest.TestCase):
    def test_boot_uses_the_notecards(self):
        npc = boot_npc()
        self.assertEqual(plain(npc.get("gName")), "Goblin Scout")
        self.assertEqual(plain(npc.get("gHP")), 30)
        self.assertEqual(plain(npc.get("gMax")), 30)
        self.assertEqual(plain(npc.get("gAtk")), 4)
        self.assertEqual(plain(npc.get("gDef")), 2)
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_OFF")))
        self.assertEqual(plain(npc.get("gResting")), 0)
        self.assertEqual(plain(npc.get("gRestore")), "defeated")
        self.assertEqual(plain(npc.get("gAggro")), "on_attack")
        self.assertEqual(plain(npc.get("gAttackDie")), 20)
        self.assertEqual(plain(npc.get("gDamageDie")), 6)
        self.assertEqual(plain(npc.get("gDamageScale")), 2)
        self.assertEqual(plain(npc.get("gCritMargin")), 10)
        self.assertEqual(plain(npc.get("gCritMult")), 2)
        self.assertEqual(npc.hovers[-1][0], "Goblin Scout\nHP 30/30\nOff")
        self.assertIn(
            "Goblin Scout is ready. State: Off. Touch the NPC and choose ON.",
            npc.owner_says,
        )
        self.assertNotIn("Could not resolve", " ".join(npc.owner_says))
        self.assertEqual(npc.links[-1][2], "0")

    def test_range_cap_warns_once_and_zero_hp_is_defeated(self):
        card = "range=50\nrange=50\nattack_die=20\n"
        npc = boot_npc({"combat": card, "npc": "name=Skeleton\nhp=0\nattack=3\ndefense=1\n"})
        self.assertEqual(plain(npc.get("gRangeM")), 10)
        self.assertEqual(npc.owner_says.count("Attack range is capped at 10m."), 1)
        self.assertEqual(plain(npc.get("gName")), "Skeleton")
        self.assertEqual(plain(npc.get("gMax")), 1)
        self.assertEqual(plain(npc.get("gHP")), 0)
        self.assertEqual(plain(npc.get("gAtk")), 3)
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_DEFEATED")))

        fresh = boot_npc()
        fresh.set("gAtk", 9)
        fresh.set("gMode", 1)
        fresh.set("gNameT", "")
        fresh.set("gHpT", -1)
        fresh.set("gAtkT", -1)
        fresh.set("gDefT", 6)
        fresh.call("commitCard")
        self.assertEqual(plain(fresh.get("gAtk")), 9)
        self.assertEqual(plain(fresh.get("gDef")), 6)

    def test_touch_rest_and_owner_controls(self):
        npc = boot_npc()
        place(npc, PLAYER, (2, 0, 0))
        touch(npc, Key(PLAYER))
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_OFF")))
        self.assertIn("The NPC is not active.", npc.dialogs[-1][1])
        self.assertNotIn("Manage", npc.dialogs[-1][2])

        touch(npc, npc.owner)
        self.assertIn("Manage", npc.dialogs[-1][2])
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_OFF")))
        click(npc, "Manage")
        click(npc, "ON")
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_IDLE")))
        self.assertIn("Goblin Scout is now Idle.", npc.region_says[-1][2])

        click(npc, "Manage")
        click(npc, "OFF")
        self.assertEqual(plain(npc.get("gResting")), 0)
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_OFF")))
        npc.set("gMenu", plain(npc.get("MENU_MANAGE")))
        npc.set("gMenuAv", PLAYER)
        click(npc, "ON", Key(PLAYER))
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_OFF")))

        npc.call("autoRest")
        self.assertEqual(plain(npc.get("gResting")), 1)
        touch(npc, Key(PLAYER))
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_IDLE")))
        self.assertEqual(plain(npc.get("gResting")), 0)

    def test_restore_rules(self):
        npc = boot_npc()
        npc.set("gHP", 0)
        npc.set("gState", plain(npc.get("ST_DEFEATED")))
        npc.call("activate", plain(npc.get("ST_DEFEATED")), OWNER)
        self.assertEqual(plain(npc.get("gHP")), 30)
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_IDLE")))

        npc.set("gRestore", "no")
        npc.set("gHP", 0)
        npc.set("gState", plain(npc.get("ST_DEFEATED")))
        npc.clear_io()
        npc.call("activate", plain(npc.get("ST_DEFEATED")), OWNER)
        self.assertEqual(plain(npc.get("gHP")), 0)
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_DEFEATED")))
        self.assertIn("Goblin Scout is defeated. HP is 0.", npc.region_says[-1][2])

        npc.set("gRestore", "always")
        npc.set("gHP", 5)
        npc.set("gState", plain(npc.get("ST_IDLE")))
        npc.call("activate", plain(npc.get("ST_IDLE")), NULL_KEY)
        self.assertEqual(plain(npc.get("gHP")), 30)

        npc.set("gRestore", "defeated")
        npc.set("gHP", 5)
        npc.call("maybeRestore", plain(npc.get("ST_IDLE")))
        self.assertEqual(plain(npc.get("gHP")), 5)
        npc.call("maybeRestore", plain(npc.get("ST_DEFEATED")))
        self.assertEqual(plain(npc.get("gHP")), 30)

    def test_resolve_miss_hit_crit_min_and_cap(self):
        npc = boot_npc()
        # Attack 8, defense 2. Dice: attack, defense, then damage when the margin is positive.
        npc.frand_queue = [0.0, 19.0]
        miss = plain(npc.call("resolve", 8, 2))
        self.assertEqual(miss, [-13, 0, 0, 1, 9, 20, 22])

        npc.frand_queue = [9.0, 9.0, 0.0]
        hit = plain(npc.call("resolve", 8, 2))
        self.assertEqual(hit, [6, 4, 0, 10, 18, 10, 12])

        npc.frand_queue = [19.0, 0.0, 0.0]
        crit = plain(npc.call("resolve", 8, 2))
        self.assertEqual(crit, [25, 26, 1, 20, 28, 1, 3])

        npc.set("gMinDamage", 10)
        npc.frand_queue = [9.0, 9.0, 0.0]
        floored = plain(npc.call("resolve", 8, 2))
        self.assertEqual(floored[1], 10)
        self.assertEqual(floored[2], 0)

        npc.set("gMinDamage", 1)
        npc.set("gDamageScale", 0)
        npc.frand_queue = [9.0, 9.0, 0.0]
        scaled = plain(npc.call("resolve", 8, 2))
        self.assertEqual(scaled[1], 7)

        npc.set("gDamageScale", 2)
        npc.set("gCritMult", 100)
        npc.frand_queue = [19.0, 0.0, 0.0]
        capped = plain(npc.call("resolve", 100000, 0))
        self.assertEqual(capped[1], 1000000)
        self.assertEqual(capped[2], 1)

        npc.clear_io()
        npc.call("narrateResult", "Hero", "Goblin Scout", -1, 0, 0, 30, 30)
        npc.call("narrateResult", "Hero", "Goblin Scout", 6, 4, 0, 26, 30)
        npc.call("narrateResult", "Hero", "Goblin Scout", 25, 26, 1, 4, 30)
        self.assertEqual(npc.says[0]["name"], "Goblin Scout")
        self.assertEqual(npc.says[0]["text"], "Miss. Goblin Scout defends.")
        self.assertEqual(npc.says[1]["name"], "Hero")
        self.assertEqual(npc.says[1]["text"], "Hit! Hero deals 4 damage to Goblin Scout. (26/30 HP)")
        self.assertEqual(
            npc.says[2]["text"],
            "Critical hit! Hero deals 26 damage to Goblin Scout. (4/30 HP)",
        )

    def test_attack_stealth_heal_and_counter(self):
        npc = boot_npc()
        npc.owners[HUD_OBJ] = Key(PLAYER)
        place(npc, PLAYER, (2, 0, 0))
        npc.profiles[PLAYER] = {"display": "Hero", "user": "hero.resident", "legacy": "Hero Resident"}
        engage(npc)
        npc.clear_io()

        npc.positions[PLAYER] = Vec(11, 0, 0)
        recv(npc, action("ATTACK"))
        self.assertEqual(
            [text for _, _, text in npc.region_says],
            ["Target is out of range.", "Maximum attack range: 10m."],
        )
        self.assertEqual(plain(npc.get("gLastPlayerAct")), 0)

        npc.positions[PLAYER] = Vec(2, 0, 0)
        npc.set("gPartyNames", ["hero.resident"])
        npc.clear_io()
        recv(npc, action("ATTACK"))
        self.assertIn("You cannot attack an ally.", [text for _, _, text in npc.region_says])
        npc.set("gPartyNames", [])

        npc.set("gState", plain(npc.get("ST_COMBAT")))
        npc.clear_io()
        recv(npc, action("STEALTH"))
        self.assertIn("Stealth is not available.", [text for _, _, text in npc.region_says])
        self.assertEqual(plain(npc.get("gLastPlayerAct")), 0)
        npc.set("gState", plain(npc.get("ST_IDLE")))
        npc.set("gHP", 30)

        npc.clear_io()
        npc.frand_queue = [0.0, 19.0]
        recv(npc, action("STEALTH"))
        texts = [item["text"] for item in npc.says]
        self.assertIn("Stealth failed.", texts)
        self.assertIn("The NPC has detected you.", texts)
        self.assertNotIn("Successful stealth attack.", texts)
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_COMBAT")))
        self.assertEqual(plain(npc.get("gHP")), 30)
        self.assertEqual(len(npc.sensors), 1)

        npc.set("gState", plain(npc.get("ST_IDLE")))
        npc.set("gHP", 30)
        npc.set("gLastPlayerAct", 0)
        npc.sensors.clear()
        npc.clear_io()
        npc.frand_queue = [19.0, 0.0, 19.0, 0.0, 0.0]
        recv(npc, action("STEALTH"))
        texts = [item["text"] for item in npc.says]
        self.assertIn("Successful stealth attack.", texts)
        self.assertIn("Critical hit! Hero deals 26 damage to Goblin Scout. (4/30 HP)", texts)
        self.assertNotIn("Stealth failed.", texts)
        self.assertEqual(plain(npc.get("gHP")), 4)
        self.assertEqual(npc.sensors, [])
        self.assertFalse(any(body.startswith("QUERY|") for _, _, body, _ in npc.links))

        npc.time += 3
        npc.set("gHP", 20)
        npc.set("gState", plain(npc.get("ST_IDLE")))
        npc.clear_io()
        npc.frand_queue = [0.0]
        recv(npc, action("HEAL"))
        self.assertIn("You can only heal an ally.", [text for _, _, text in npc.region_says])
        npc.set("gPartyNames", ["hero.resident"])
        npc.clear_io()
        npc.frand_queue = [0.0]
        recv(npc, action("HEAL"))
        self.assertEqual(plain(npc.get("gHP")), 21)
        self.assertEqual(npc.says[-1]["text"], "Hero heals Goblin Scout for 1. (21/30 HP)")

        npc.set("gHP", 30)
        npc.time += 3
        npc.clear_io()
        recv(npc, action("HEAL"))
        self.assertIn("Goblin Scout is already at full HP.", [text for _, _, text in npc.region_says])

        npc.set("gPartyNames", [])
        npc.set("gState", plain(npc.get("ST_IDLE")))
        npc.set("gHP", 30)
        npc.time += 3
        npc.clear_io()
        npc.frand_queue = [0.0, 19.0]
        recv(npc, action("ATTACK"))
        self.assertEqual(plain(npc.get("gHP")), 30)
        npc.clear_io()
        recv(npc, action("ATTACK"))
        self.assertIn("Wait a moment before acting again.", [text for _, _, text in npc.region_says])

        npc.time += 3
        npc.clear_io()
        npc.frand_queue = [19.0, 0.0, 0.0]
        recv(npc, action("COUNTER", defending=1))
        texts = [item["text"] for item in npc.says]
        self.assertIn("Goblin Scout attacks Hero.", texts)
        self.assertIn("Hero is defending (+2 Defense).", texts)
        self.assertIn("Hit! Goblin Scout deals 5 damage to Hero. (120/125 HP)", texts)
        self.assertTrue(any(body == f"HPDELTA|{PLAYER}|-5" for _, _, body, _ in npc.links))

    def test_forced_target_sight_rest_and_party(self):
        npc = boot_npc()
        place(npc, PLAYER, (2, 0, 0))
        engage(npc)
        # OTHER is not in the region, so the forced target matches nobody.
        # The valid player nearby must not be scanned either.
        npc.call("setTargetText", OTHER)
        npc.clear_io()
        npc.call("startCounter")
        self.assertEqual(npc.sensors, [])
        self.assertFalse(any(body.startswith("QUERY|") for _, _, body, _ in npc.links))

        npc.set("gForced", NULL_KEY)
        npc.set("gState", plain(npc.get("ST_ACTIVE")))
        npc.set("gAggro", "on_sight")
        npc.set("gLastScan", 0)
        npc.clear_io()
        npc.call("timer")
        self.assertEqual(len(npc.sensors), 1)

        npc.sensors.clear()
        npc.set("gState", plain(npc.get("ST_IDLE")))
        npc.call("timer")
        self.assertEqual(npc.sensors, [])

        npc.set("gState", plain(npc.get("ST_COMBAT")))
        npc.set("gLastActivity", WHEN - 40)
        npc.set("gAggro", "on_attack")
        npc.call("timer")
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_IDLE")))

        npc.set("gLastActivity", npc.time - 300)
        npc.call("timer")
        self.assertEqual(plain(npc.get("gState")), plain(npc.get("ST_OFF")))
        self.assertEqual(plain(npc.get("gResting")), 1)

        npc.set("gReqId", "req-9")
        npc.set("gReqKind", "ATTACK")
        npc.set("gReqAv", PLAYER)
        npc.set("gReqTime", npc.time - 9)
        npc.clear_io()
        npc.call("timer")
        heard = [text for _, _, text in npc.region_says]
        self.assertEqual(
            heard,
            ["No SL RPG Combat HUD detected.", "Wear the HUD to take this action."],
        )
        npc.set("gReqId", "req-9")
        npc.set("gReqKind", "COUNTER")
        npc.set("gReqTime", npc.time - 9)
        npc.clear_io()
        npc.call("timer")
        self.assertEqual(npc.region_says, [])
        self.assertEqual(plain(npc.get("gReqId")), "")

        npc.call("setPartyText", "Hero.Resident")
        self.assertNotIn("hero.resident", npc.user_keys)
        npc.deliver()
        self.assertIn("Could not resolve avatar: hero.resident", " ".join(npc.owner_says))
        npc.user_keys["hero.resident"] = PLAYER
        npc.call("setPartyText", "Hero.Resident")
        npc.deliver()
        self.assertIn("hero.resident", plain(npc.get("gPartyNames")))
        self.assertIn(PLAYER, plain(npc.get("gPartyKeys")))

        npc.call("addParty", PLAYER)
        self.assertIn(PLAYER, plain(npc.get("gPartyKeys")))
        npc.call("setTargetText", "clear")
        self.assertEqual(plain(npc.get("gForced")), NULL_KEY.value)

    def test_can_stealth_only_at_full_hp_outside_combat(self):
        npc = boot_npc()
        npc.set("gHP", 30)
        npc.set("gMax", 30)
        for state in ("ST_OFF", "ST_COMBAT", "ST_DEFEATED"):
            npc.set("gState", plain(npc.get(state)))
            self.assertEqual(plain(npc.call("canStealth")), 0)
        npc.set("gState", plain(npc.get("ST_IDLE")))
        self.assertEqual(plain(npc.call("canStealth")), 1)
        npc.set("gState", plain(npc.get("ST_ACTIVE")))
        self.assertEqual(plain(npc.call("canStealth")), 1)
        npc.set("gHP", 29)
        self.assertEqual(plain(npc.call("canStealth")), 0)

    def test_reload_resets_and_stranger_cannot_forge_the_owner(self):
        npc = boot_npc()
        npc.owners[HUD_OBJ] = Key(OTHER)
        place(npc, PLAYER, (2, 0, 0))
        engage(npc)
        before = plain(npc.get("gHP"))
        npc.clear_io()
        recv(npc, action("ATTACK"))
        self.assertEqual(plain(npc.get("gHP")), before)
        self.assertEqual(npc.says, [])

        npc.clear_io()
        npc.call("link_message", 1, plain(npc.get("LINK_RECV")), "NOCHAR|" + PLAYER + "|nope", HUD_OBJ)
        self.assertEqual(npc.region_says, [])

        npc.linkset["n.set"] = "1"
        npc.call("changed", plain(npc.get("CHANGED_INVENTORY")))
        self.assertTrue(npc.did_reset)
        self.assertEqual(npc.linkset.get("n.set"), "1")


if __name__ == "__main__":
    unittest.main()
