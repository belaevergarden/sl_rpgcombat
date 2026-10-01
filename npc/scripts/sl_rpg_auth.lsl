// SL RPG Combat — original combat network.
//
// This script is the only place that knows the channel and the password.
// Drop the same file into the player HUD and the NPC. The two copies must
// stay identical. Gameplay scripts talk to it with link messages and never
// learn the channel or the password.
//
// A modified build cannot use an original HUD or NPC. Change all three
// identity values together — SEC_CHANNEL, SEC_PASSWORD, and SEC_BUILD —
// in both copies. Peers that fail this identity are ignored.
//
// The password separates combat networks. It is not hidden from anyone who
// can read this file. For a private deployment, replace all three values
// and do not publish that copy.

integer SEC_CHANNEL = -1859789070;
string SEC_PASSWORD = "dc45562fdb883d1f1df96fb8dd1e2a993715daa091bfe799";
string SEC_BUILD = "official-1";
integer SEC_VERSION = 1;
integer SEC_SKEW_PAST = 25;
integer SEC_SKEW_FUTURE = 10;

integer LINK_SEND = 51001;
integer LINK_RECV = 51002;
integer LINK_LISTEN = 51003;
integer LINK_READY = 51004;

integer gListenOn;
integer gHandle;
list gSeen;
integer gWarnAt;
integer gSeq;

string macFor(string body, string ts, string nonce) {
    return llSHA1String(SEC_PASSWORD + "|" + (string)SEC_CHANNEL + "|" + SEC_BUILD + "|" + (string)SEC_VERSION + "|" + ts + "|" + nonce + "|" + body);
}

warnOnce(string text) {
    integer now;
    now = llGetUnixTime();
    if (now - gWarnAt < 60) return;
    gWarnAt = now;
    llOwnerSay(text);
}

setListen(integer on) {
    if (on) {
        if (!gListenOn) {
            gHandle = llListen(SEC_CHANNEL, "", NULL_KEY, "");
            gListenOn = TRUE;
        }
    }
    else if (gListenOn) {
        llListenRemove(gHandle);
        gListenOn = FALSE;
        gHandle = 0;
    }
}

doSend(key target, string body) {
    string ts;
    string nonce;
    string mac;
    string wire;
    if (target == NULL_KEY) return;
    if (llStringLength(body) < 1 || llStringLength(body) > 700) return;
    if (llSubStringIndex(body, "\n") != -1) return;
    gSeq = gSeq + 1;
    ts = (string)llGetUnixTime();
    nonce = ts + "-" + (string)gSeq + "-" + (string)((integer)llFrand(1000000.0) + 1);
    mac = macFor(body, ts, nonce);
    wire = "SLRPG\n" + (string)SEC_VERSION + "\n" + SEC_BUILD + "\n" + ts + "\n" + nonce + "\n" + body + "\n" + mac;
    if (llStringLength(wire) > 1024) return;
    llRegionSayTo(target, SEC_CHANNEL, wire);
}

default {
    state_entry() {
        gSeen = [];
        // The HUD keeps this listen. An NPC turns it off while OFF.
        setListen(TRUE);
        llMessageLinked(LINK_SET, LINK_READY, SEC_BUILD, NULL_KEY);
        llOwnerSay("SL RPG Combat network ready. Build " + SEC_BUILD + ".");
    }

    on_rez(integer start) {
        llResetScript();
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_SEND) doSend(id, str);
        else if (num == LINK_LISTEN) setListen(str == "1");
    }

    listen(integer channel, string name, key id, string message) {
        list parts;
        string build;
        string ts;
        string nonce;
        string body;
        string mac;
        integer when;
        integer now;
        if (channel != SEC_CHANNEL) return;
        if (id == llGetKey()) return;
        if (llGetSubString(message, 0, 4) != "SLRPG") return;
        if (llStringLength(message) > 1024) return;
        parts = llParseStringKeepNulls(message, ["\n"], []);
        if (llGetListLength(parts) != 7) return;
        if (llList2String(parts, 0) != "SLRPG") return;
        if (llList2String(parts, 1) != (string)SEC_VERSION) {
            warnOnce("Ignored a message from a different SL RPG Combat version.");
            return;
        }
        build = llList2String(parts, 2);
        if (build != SEC_BUILD) {
            if (llStringLength(build) > 40) build = llGetSubString(build, 0, 39);
            warnOnce("Ignored a message from build " + build + ". This object is " + SEC_BUILD + ".");
            return;
        }
        ts = llList2String(parts, 3);
        nonce = llList2String(parts, 4);
        body = llList2String(parts, 5);
        mac = llList2String(parts, 6);
        when = (integer)ts;
        now = llGetUnixTime();
        if (when < now - SEC_SKEW_PAST || when > now + SEC_SKEW_FUTURE) return;
        if (llStringLength(nonce) < 4 || llStringLength(nonce) > 48) return;
        if (llStringLength(mac) != 40) return;
        if (llListFindList(gSeen, [nonce]) != -1) return;
        if (mac != macFor(body, ts, nonce)) {
            warnOnce("Ignored an unauthenticated combat message.");
            return;
        }
        gSeen = gSeen + [nonce];
        if (llGetListLength(gSeen) > 24) gSeen = llDeleteSubList(gSeen, 0, 0);
        llMessageLinked(LINK_SET, LINK_RECV, body, id);
    }
}
