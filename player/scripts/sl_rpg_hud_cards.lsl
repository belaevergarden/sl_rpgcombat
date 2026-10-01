// SL RPG Combat — HUD notecard reader.
// Put this in the HUD root prim with sl_rpg_auth, sl_rpg_hud, and sl_rpg_hud_ui.
// Save every script with the Mono compiler checked.
// User-facing text is English.

integer LINK_BODY = 51011;

integer gRangeM;
integer gDefendBonus;
list gJobs;
key gQuery;
string gCard;
integer gLine;
integer gMode;
integer gHpT;
integer gAtkT;
integer gDefT;
string gNameT;
integer gDone;

string sanitize(string value) {
    value = llDumpList2String(llParseString2List(value, ["|", "\n", "\r"], []), " ");
    value = llStringTrim(value, STRING_TRIM);
    if (llStringLength(value) > 40) value = llGetSubString(value, 0, 39);
    return value;
}

sendRules() {
    llMessageLinked(LINK_SET, LINK_BODY, "RULES|" + (string)gRangeM + "|" + (string)gDefendBonus, NULL_KEY);
}

parseLine(string raw) {
    string line;
    integer eq;
    string keyName;
    string value;
    line = llDumpList2String(llParseString2List(raw, ["\r"], []), "");
    line = llStringTrim(line, STRING_TRIM);
    if (line == "") return;
    if (llGetSubString(line, 0, 0) == "#") return;
    eq = llSubStringIndex(line, "=");
    if (eq < 1) return;
    keyName = llToLower(llStringTrim(llGetSubString(line, 0, eq - 1), STRING_TRIM));
    value = llStringTrim(llGetSubString(line, eq + 1, -1), STRING_TRIM);
    if (gMode == 0) {
        if (keyName == "range") {
            gRangeM = (integer)value;
            if (gRangeM < 1) gRangeM = 1;
            if (gRangeM > 10) {
                gRangeM = 10;
                llOwnerSay("Attack range is capped at 10m.");
            }
            sendRules();
        }
        else if (keyName == "defend_bonus") {
            gDefendBonus = (integer)value;
            sendRules();
        }
        return;
    }
    if (keyName == "name") gNameT = sanitize(value);
    else if (keyName == "hp") gHpT = (integer)value;
    else if (keyName == "attack") gAtkT = (integer)value;
    else if (keyName == "defense") gDefT = (integer)value;
}

commitCard() {
    if (gMode == 0) return;
    llMessageLinked(LINK_SET, LINK_BODY, "ADD|" + (string)gMode + "|" + gCard + "|" + gNameT + "|" + (string)gHpT + "|" + (string)gAtkT + "|" + (string)gDefT, NULL_KEY);
}

pump() {
    string job;
    if (gQuery != NULL_KEY) return;
    if (llGetListLength(gJobs) == 0) {
        if (gDone) return;
        gDone = TRUE;
        sendRules();
        llMessageLinked(LINK_SET, LINK_BODY, "DONE", NULL_KEY);
        return;
    }
    job = llList2String(gJobs, 0);
    gJobs = llDeleteSubList(gJobs, 0, 0);
    if (llGetInventoryType(job) != INVENTORY_NOTECARD) {
        pump();
        return;
    }
    gCard = job;
    gLine = 0;
    gHpT = 0;
    gAtkT = 0;
    gDefT = 0;
    gNameT = "";
    gMode = 3;
    if (job == "combat") gMode = 0;
    else if (llSubStringIndex(job, "gen_") == 0) gMode = 1;
    else if (llSubStringIndex(job, "race_") == 0) gMode = 2;
    gQuery = llGetNotecardLine(gCard, 0);
}

discover() {
    integer n;
    integer i;
    string name;
    integer hasCombat;
    list presets;
    n = llGetInventoryNumber(INVENTORY_NOTECARD);
    for (i = 0; i < n; i += 1) {
        name = llGetInventoryName(INVENTORY_NOTECARD, i);
        if (name == "combat") hasCombat = TRUE;
        else if (llSubStringIndex(name, "gen_") == 0 || llSubStringIndex(name, "race_") == 0 || llSubStringIndex(name, "class_") == 0) {
            presets = presets + [name];
        }
    }
    gJobs = presets;
    if (hasCombat) gJobs = ["combat"] + gJobs;
    else llOwnerSay("Notecard \"combat\" is missing. Using a range of 10m.");
}

default {
    state_entry() {
        gRangeM = 10;
        gDefendBonus = 2;
        gQuery = NULL_KEY;
        discover();
        pump();
    }

    on_rez(integer start) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) llResetScript();
        if (change & CHANGED_INVENTORY) llResetScript();
    }

    link_message(integer sender, integer num, string str, key id) {
        if (str == "RST") llResetScript();
    }

    dataserver(key query, string data) {
        if (query != gQuery) return;
        if (data == EOF) {
            gQuery = NULL_KEY;
            commitCard();
            pump();
            return;
        }
        parseLine(data);
        gLine = gLine + 1;
        gQuery = llGetNotecardLine(gCard, gLine);
    }
}
