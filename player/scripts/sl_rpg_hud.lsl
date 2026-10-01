// SL RPG Combat — HUD core.
// Put this in the HUD root prim with sl_rpg_auth, sl_rpg_hud_ui, and
// sl_rpg_hud_cards. Save every script with the Mono compiler checked.
// User-facing text is English.
// If you change gameplay, also change SEC_CHANNEL, SEC_PASSWORD, and
// SEC_BUILD in both copies of sl_rpg_auth.lsl.

integer LINK_SEND = 51001;
integer LINK_RECV = 51002;
integer LINK_LISTEN = 51003;
integer LINK_READY = 51004;
integer LINK_BODY = 51011;

integer gReadyChar;
string gName;
integer gHP;
integer gMax;
integer gAtk;
integer gDef;
integer gDefending;
integer gRangeM;
integer gDefendBonus;
string gBuild;
integer gWait;
integer gWaitAt;
key gTarget;
string gTargetName;

string sanitize(string value) {
    value = llDumpList2String(llParseString2List(value, ["|", "\n", "\r"], []), " ");
    value = llStringTrim(value, STRING_TRIM);
    if (llStringLength(value) > 40) value = llGetSubString(value, 0, 39);
    return value;
}

string opOf(string body) {
    integer cut;
    cut = llSubStringIndex(body, "\n");
    if (cut < 0) cut = llSubStringIndex(body, "|");
    if (cut < 0) return body;
    return llGetSubString(body, 0, cut - 1);
}

rangeFail() {
    llOwnerSay("Target is out of range.");
    llOwnerSay("Maximum attack range: " + (string)gRangeM + "m.");
}

integer inRange() {
    vector pos;
    if (gTarget == NULL_KEY) return FALSE;
    pos = llList2Vector(llGetObjectDetails(gTarget, [OBJECT_POS]), 0);
    if (pos == ZERO_VECTOR) return FALSE;
    if (llVecDist(llGetPos(), pos) > (float)gRangeM) return FALSE;
    return TRUE;
}

armWait() {
    gWait = TRUE;
    gWaitAt = llGetUnixTime();
    llSetTimerEvent(1.0);
}

sendAction(string kind) {
    string body;
    if (!gReadyChar) {
        llOwnerSay("Create a character first.");
        return;
    }
    if (gTarget == NULL_KEY) {
        llOwnerSay("Select a target by clicking an NPC.");
        return;
    }
    if (!inRange()) {
        rangeFail();
        return;
    }
    body = "ACTION|" + (string)llGetOwner() + "|" + kind + "|hud|" + sanitize(gName) + "|" + (string)gAtk + "|" + (string)gDef + "|" + (string)gHP + "|" + (string)gMax + "|0";
    llMessageLinked(LINK_SET, LINK_SEND, body, gTarget);
    armWait();
}

replyQuery(string kind, string req) {
    string body;
    string flag;
    flag = "0";
    if (!gReadyChar) {
        body = "NOCHAR|" + (string)llGetOwner() + "|" + req;
        llMessageLinked(LINK_SET, LINK_SEND, body, gTarget);
        return;
    }
    if (kind == "COUNTER" && gDefending) {
        flag = "1";
        gDefending = FALSE;
        llMessageLinked(LINK_SET, LINK_BODY, "DEF|0", NULL_KEY);
    }
    body = "ACTION|" + (string)llGetOwner() + "|" + kind + "|" + req + "|" + sanitize(gName) + "|" + (string)gAtk + "|" + (string)gDef + "|" + (string)gHP + "|" + (string)gMax + "|" + flag;
    llMessageLinked(LINK_SET, LINK_SEND, body, gTarget);
}

onStats(string body) {
    list fields;
    fields = llParseStringKeepNulls(body, ["|"], []);
    gReadyChar = (integer)llList2String(fields, 1);
    gHP = (integer)llList2String(fields, 2);
    gMax = (integer)llList2String(fields, 3);
    gAtk = (integer)llList2String(fields, 4);
    gDef = (integer)llList2String(fields, 5);
    gName = llList2String(fields, 6);
    if (gName == "") gName = "Adventurer";
}

onRules(string body) {
    list fields;
    fields = llParseStringKeepNulls(body, ["|"], []);
    gRangeM = (integer)llList2String(fields, 1);
    gDefendBonus = (integer)llList2String(fields, 2);
    if (gRangeM < 1) gRangeM = 1;
    if (gRangeM > 10) gRangeM = 10;
}

onRecv(string body, key speaker) {
    list fields;
    string op;
    integer delta;
    vector pos;
    fields = llParseStringKeepNulls(body, ["|"], []);
    op = llList2String(fields, 0);
    if (op == "QUERY") {
        if ((key)llList2String(fields, 1) != llGetOwner()) return;
        pos = llList2Vector(llGetObjectDetails(speaker, [OBJECT_POS]), 0);
        if (pos == ZERO_VECTOR) return;
        if (llVecDist(llGetPos(), pos) > (float)gRangeM) return;
        gTarget = speaker;
        gTargetName = sanitize(llList2String(fields, 4));
        if (gTargetName == "") gTargetName = "NPC";
        llMessageLinked(LINK_SET, LINK_BODY, "TGT|" + (string)gTarget + "|" + gTargetName, NULL_KEY);
        replyQuery(llList2String(fields, 2), llList2String(fields, 3));
        return;
    }
    if (op == "ACK") {
        if ((key)llList2String(fields, 1) != llGetOwner()) return;
        gWait = FALSE;
        llSetTimerEvent(0.0);
        return;
    }
    if (op == "HPDELTA") {
        if ((key)llList2String(fields, 1) != llGetOwner()) return;
        if (!gReadyChar) return;
        pos = llList2Vector(llGetObjectDetails(speaker, [OBJECT_POS]), 0);
        if (pos == ZERO_VECTOR) return;
        if (llVecDist(llGetPos(), pos) > (float)(gRangeM + 5)) {
            llOwnerSay("Ignored a health change from out of range.");
            return;
        }
        delta = (integer)llList2String(fields, 2);
        gHP = gHP + delta;
        if (gHP < 0) gHP = 0;
        if (gHP > gMax) gHP = gMax;
        llMessageLinked(LINK_SET, LINK_BODY, "HP|" + (string)gHP + "|" + (string)gMax, NULL_KEY);
        llOwnerSay("Your HP is now " + (string)gHP + "/" + (string)gMax + ".");
        if (gHP == 0) llOwnerSay("You are at 0 HP.");
    }
}

onBody(string body) {
    string op;
    op = opOf(body);
    if (op == "STATS") onStats(body);
    else if (op == "RULES") onRules(body);
    else if (op == "ACT") sendAction(llGetSubString(body, 4, -1));
    else if (op == "DEF") gDefending = (integer)llGetSubString(body, 4, -1);
    else if (op == "CLR") {
        gTarget = NULL_KEY;
        gTargetName = "";
    }
}

default {
    state_entry() {
        gRangeM = 10;
        gDefendBonus = 2;
        gTarget = NULL_KEY;
        gName = "Adventurer";
    }

    on_rez(integer start) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) llResetScript();
        if (change & CHANGED_INVENTORY) llResetScript();
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_READY) {
            gBuild = str;
            llMessageLinked(LINK_SET, LINK_LISTEN, "1", NULL_KEY);
        }
        else if (num == LINK_RECV) onRecv(str, id);
        else if (num == LINK_BODY) onBody(str);
    }

    timer() {
        if (gWait && llGetUnixTime() - gWaitAt > 8) {
            gWait = FALSE;
            llOwnerSay("The NPC did not respond.");
            llOwnerSay("It may be off, or it may not belong to this combat network.");
            llSetTimerEvent(0.0);
        }
    }
}
