// SL RPG Combat — NPC core.
// Put this in the NPC root prim with sl_rpg_auth, sl_rpg_npc_ui, and
// sl_rpg_npc_fight. Save every script with the Mono compiler checked.
// User-facing text is English.
// If you change gameplay, also change SEC_CHANNEL, SEC_PASSWORD, and
// SEC_BUILD in both copies of sl_rpg_auth.lsl.

integer LINK_SEND = 51001;
integer LINK_RECV = 51002;
integer LINK_LISTEN = 51003;
integer LINK_READY = 51004;
integer LINK_BODY = 51011;

integer ST_OFF = 0;
integer ST_IDLE = 1;
integer ST_ACTIVE = 2;
integer ST_COMBAT = 3;
integer ST_DEFEATED = 4;

integer MENU_ROOT = 1;
integer MENU_MANAGE = 2;

integer TEXT_HP = 1;
integer TEXT_ATK = 2;
integer TEXT_DEF = 3;
integer TEXT_NAME = 4;
integer TEXT_PARTY = 5;
integer TEXT_TARGET = 6;

string gName;
integer gHP;
integer gMax;
integer gAtk;
integer gDef;
integer gState;
integer gResting;
integer gReady;
integer gBooted;
integer gDidOverride;
string gBuild;

integer gRangeM;
integer gRest;
string gRestore;
string gAggro;
integer gCombatTimeout;
integer gScanEvery;
integer gLastActivity;
integer gLastScan;
integer gLastPlayerAct;
integer gWarnedRange;

list gPartyNames;
list gPartyKeys;
key gForced;
string gForcedName;
list gFoeKeys;
list gFoeHP;

string gReqId;
string gReqKind;
key gReqAv;
integer gReqTime;
integer gSeq;

list gJobs;
key gQuery;
string gQueryKind;
string gCard;
integer gMode;
string gPendingName;
integer gHpT;
integer gAtkT;
integer gDefT;
string gNameT;
integer gSensorBusy;
string gSense;

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

string restOf(string body) {
    integer cut;
    cut = llSubStringIndex(body, "\n");
    if (cut < 0) return "";
    return llGetSubString(body, cut + 1, -1);
}

string stateLabel() {
    if (gState == ST_OFF) {
        if (gResting) return "Resting";
        return "Off";
    }
    if (gState == ST_IDLE) return "Idle";
    if (gState == ST_ACTIVE) return "Active";
    if (gState == ST_COMBAT) return "Combat";
    return "Defeated";
}

refreshText() {
    vector color;
    color = <0.45, 0.45, 0.5>;
    if (gState == ST_OFF) color = <0.55, 0.55, 0.55>;
    else if (gState == ST_IDLE) color = <0.55, 0.85, 0.55>;
    else if (gState == ST_ACTIVE) color = <0.95, 0.9, 0.35>;
    else if (gState == ST_COMBAT) color = <1.0, 0.35, 0.28>;
    llSetText(gName + "\nHP " + (string)gHP + "/" + (string)gMax + "\n" + stateLabel(), color, 1.0);
}

pushListen() {
    string flag;
    flag = "0";
    if (gState != ST_OFF) flag = "1";
    llMessageLinked(LINK_SET, LINK_LISTEN, flag, NULL_KEY);
}

armTimer() {
    if (gState == ST_OFF) llSetTimerEvent(60.0);
    else if (gState == ST_COMBAT || gState == ST_ACTIVE) llSetTimerEvent(2.0);
    else llSetTimerEvent(5.0);
}

saveRuntime() {
    if (!gReady) return;
    llLinksetDataWrite("n.set", "1");
    llLinksetDataWrite("n.name", gName);
    llLinksetDataWrite("n.max", (string)gMax);
    llLinksetDataWrite("n.hp", (string)gHP);
    llLinksetDataWrite("n.atk", (string)gAtk);
    llLinksetDataWrite("n.def", (string)gDef);
    llLinksetDataWrite("n.state", (string)gState);
    llLinksetDataWrite("n.resting", (string)gResting);
    llLinksetDataWrite("n.target", (string)gForced);
    llLinksetDataWrite("n.targetname", gForcedName);
    llLinksetDataWrite("n.partyset", "1");
    llLinksetDataWrite("n.party", llDumpList2String(gPartyNames, ","));
}

enter(integer next) {
    gState = next;
    refreshText();
    pushListen();
    armTimer();
    saveRuntime();
}

tell(key av, string text) {
    if (av == NULL_KEY || text == "") return;
    llRegionSayTo(av, 0, text);
}

rangeFail(key av) {
    tell(av, "Target is out of range.");
    tell(av, "Maximum attack range: " + (string)gRangeM + "m.");
}

integer inRangeOf(key id) {
    vector pos;
    if (id == NULL_KEY) return FALSE;
    pos = llList2Vector(llGetObjectDetails(id, [OBJECT_POS]), 0);
    if (pos == ZERO_VECTOR) return FALSE;
    if (llVecDist(llGetPos(), pos) > (float)gRangeM) return FALSE;
    return TRUE;
}

integer isAllyKey(key av) {
    string userName;
    string displayName;
    string legacy;
    if (av == NULL_KEY) return FALSE;
    if (llListFindList(gPartyKeys, [av]) != -1) return TRUE;
    userName = llToLower(llGetUsername(av));
    displayName = llToLower(llGetDisplayName(av));
    legacy = llToLower(llKey2Name(av));
    if (userName != "" && llListFindList(gPartyNames, [userName]) != -1) return TRUE;
    if (displayName != "" && llListFindList(gPartyNames, [displayName]) != -1) return TRUE;
    if (legacy != "" && llListFindList(gPartyNames, [legacy]) != -1) return TRUE;
    return FALSE;
}

integer foeKnownDead(key av) {
    integer index;
    index = llListFindList(gFoeKeys, [av]);
    if (index == -1) return FALSE;
    if (llList2Integer(gFoeHP, index) <= 0) return TRUE;
    return FALSE;
}

integer validFoeKey(key av) {
    if (llGetAgentSize(av) == ZERO_VECTOR) return FALSE;
    if (!inRangeOf(av)) return FALSE;
    if (isAllyKey(av)) return FALSE;
    if (foeKnownDead(av)) return FALSE;
    return TRUE;
}

remember(key av, integer hp) {
    integer index;
    if (av == NULL_KEY) return;
    if (hp < 0) hp = 0;
    index = llListFindList(gFoeKeys, [av]);
    if (index == -1) {
        if (llGetListLength(gFoeKeys) > 40) {
            gFoeKeys = llDeleteSubList(gFoeKeys, 0, 0);
            gFoeHP = llDeleteSubList(gFoeHP, 0, 0);
        }
        gFoeKeys = gFoeKeys + [av];
        gFoeHP = gFoeHP + [hp];
    }
    else gFoeHP = llListReplaceList(gFoeHP, [hp], index, index);
}

ack(key av) {
    llMessageLinked(LINK_SET, LINK_SEND, "ACK|" + (string)av, av);
}

beginQuery(key av, string kind) {
    string req;
    gSeq = gSeq + 1;
    req = (string)llGetUnixTime() + "-" + (string)gSeq;
    gReqId = req;
    gReqKind = kind;
    gReqAv = av;
    gReqTime = llGetUnixTime();
    llMessageLinked(LINK_SET, LINK_SEND, "QUERY|" + (string)av + "|" + kind + "|" + req + "|" + sanitize(gName), av);
}

startCounter() {
    if (gReqId != "") return;
    if (gState == ST_OFF || gState == ST_DEFEATED) return;
    if (gForced != NULL_KEY) {
        if (validFoeKey(gForced)) beginQuery(gForced, "COUNTER");
        return;
    }
    if (gSensorBusy) return;
    gSense = "counter";
    gSensorBusy = TRUE;
    llSensor("", NULL_KEY, AGENT, (float)gRangeM, PI);
}

integer canStealth() {
    if (gState == ST_OFF || gState == ST_COMBAT || gState == ST_DEFEATED) return FALSE;
    if (gHP <= 0 || gHP != gMax) return FALSE;
    return TRUE;
}

maybeRestore(integer fromState) {
    if (gRestore == "always") gHP = gMax;
    else if (gRestore == "defeated" && fromState == ST_DEFEATED) gHP = gMax;
}

activate(integer fromState, key who) {
    gResting = FALSE;
    gLastActivity = llGetUnixTime();
    maybeRestore(fromState);
    if (gHP <= 0) {
        enter(ST_DEFEATED);
        tell(who, gName + " is defeated. HP is 0.");
        return;
    }
    if (gAggro == "on_sight") enter(ST_ACTIVE);
    else enter(ST_IDLE);
    tell(who, gName + " is now " + stateLabel() + ".");
}

turnOff(key who) {
    gResting = FALSE;
    gReqId = "";
    enter(ST_OFF);
    tell(who, gName + " is off.");
}

autoRest() {
    gResting = TRUE;
    gReqId = "";
    enter(ST_OFF);
}

setNpcHp(integer value) {
    if (value < 0) value = 0;
    if (value > 100000) value = 100000;
    if (value > gMax) gMax = value;
    gHP = value;
    gLastActivity = llGetUnixTime();
    if (gHP <= 0) enter(ST_DEFEATED);
    else if (gState == ST_DEFEATED || gState == ST_OFF) {
        gResting = FALSE;
        if (gAggro == "on_sight") enter(ST_ACTIVE);
        else enter(ST_IDLE);
    }
    else {
        refreshText();
        saveRuntime();
    }
}

sendShow(integer menu, key av, string prompt, list labels) {
    llMessageLinked(LINK_SET, LINK_BODY, "SHOW\n" + (string)menu + "\n" + (string)av + "\n" + llDumpList2String(labels, "|") + "\n" + prompt, NULL_KEY);
}

sendBox(integer which, key av, string prompt) {
    llMessageLinked(LINK_SET, LINK_BODY, "BOX\n" + (string)which + "\n" + (string)av + "\n" + prompt, NULL_KEY);
}

sendAttack(key av, string player, integer atkStat, integer stealth) {
    llMessageLinked(LINK_SET, LINK_BODY, "J|ATTACK|" + (string)av + "|" + player + "|" + (string)atkStat + "|" + (string)stealth + "|" + (string)gHP + "|" + (string)gMax + "|" + (string)gAtk + "|" + (string)gDef + "|" + sanitize(gName), NULL_KEY);
}

sendHeal(key av, string player) {
    llMessageLinked(LINK_SET, LINK_BODY, "J|HEAL|" + (string)av + "|" + player + "|" + (string)gHP + "|" + (string)gMax + "|" + sanitize(gName), NULL_KEY);
}

sendCounter(key av, string player, integer defStat, integer hp, integer maxHp, integer defending) {
    llMessageLinked(LINK_SET, LINK_BODY, "J|COUNTER|" + (string)av + "|" + player + "|" + (string)defStat + "|" + (string)hp + "|" + (string)maxHp + "|" + (string)defending + "|" + (string)gAtk + "|" + sanitize(gName), NULL_KEY);
}

handleAction(string body, key speaker) {
    list fields;
    key av;
    key speakerOwner;
    string kind;
    string req;
    string player;
    integer atkStat;
    integer defStat;
    integer hp;
    integer maxHp;
    integer defending;
    integer stealth;
    fields = llParseStringKeepNulls(body, ["|"], []);
    if (llList2String(fields, 0) != "ACTION") return;
    av = (key)llList2String(fields, 1);
    speakerOwner = llGetOwnerKey(speaker);
    if (speakerOwner == NULL_KEY || speakerOwner != av) return;
    kind = llList2String(fields, 2);
    req = llList2String(fields, 3);
    if (req != "hud" && req != gReqId) return;
    if (req == gReqId && kind != gReqKind && gReqKind != "") return;
    gReqId = "";
    player = sanitize(llList2String(fields, 4));
    atkStat = (integer)llList2String(fields, 5);
    defStat = (integer)llList2String(fields, 6);
    hp = (integer)llList2String(fields, 7);
    maxHp = (integer)llList2String(fields, 8);
    defending = (integer)llList2String(fields, 9);
    if (atkStat < 0) atkStat = 0;
    if (defStat < 0) defStat = 0;
    if (atkStat > 100000) atkStat = 100000;
    if (defStat > 100000) defStat = 100000;
    if (hp < 0) hp = 0;
    if (maxHp < 1) maxHp = 1;
    remember(av, hp);
    if (kind != "COUNTER" && llGetUnixTime() - gLastPlayerAct < 2) {
        tell(av, "Wait a moment before acting again.");
        ack(av);
        return;
    }
    if (kind == "COUNTER") {
        if (gState == ST_OFF || gState == ST_DEFEATED) {
            ack(av);
            return;
        }
        if (!validFoeKey(av)) {
            ack(av);
            return;
        }
        if (hp <= 0) {
            ack(av);
            return;
        }
        gLastActivity = llGetUnixTime();
        sendCounter(av, player, defStat, hp, maxHp, defending);
        return;
    }
    if (kind == "HEAL") {
        if (gState == ST_OFF) {
            tell(av, "The NPC is not active.");
            ack(av);
            return;
        }
        if (!isAllyKey(av)) {
            tell(av, "You can only heal an ally.");
            ack(av);
            return;
        }
        if (!inRangeOf(av)) {
            rangeFail(av);
            ack(av);
            return;
        }
        if (gHP >= gMax) {
            tell(av, gName + " is already at full HP.");
            ack(av);
            return;
        }
        gLastActivity = llGetUnixTime();
        gLastPlayerAct = llGetUnixTime();
        sendHeal(av, player);
        return;
    }
    if (kind == "STEALTH" || kind == "ATTACK") {
        stealth = FALSE;
        if (kind == "STEALTH") stealth = TRUE;
        if (gState == ST_OFF) {
            tell(av, "The NPC is not active.");
            ack(av);
            return;
        }
        if (isAllyKey(av)) {
            tell(av, "You cannot attack an ally.");
            ack(av);
            return;
        }
        if (!inRangeOf(av)) {
            rangeFail(av);
            ack(av);
            return;
        }
        if (gState == ST_DEFEATED) {
            tell(av, "The NPC is defeated.");
            ack(av);
            return;
        }
        if (stealth) {
            if (!canStealth()) {
                tell(av, "Stealth is not available.");
                ack(av);
                return;
            }
        }
        gLastActivity = llGetUnixTime();
        gLastPlayerAct = llGetUnixTime();
        sendAttack(av, player, atkStat, stealth);
        return;
    }
    ack(av);
}

onRecv(string body, key speaker) {
    list fields;
    string op;
    key av;
    fields = llParseStringKeepNulls(body, ["|"], []);
    op = llList2String(fields, 0);
    if (op == "NOCHAR") {
        av = (key)llList2String(fields, 1);
        if (llGetOwnerKey(speaker) != av) return;
        if (llList2String(fields, 2) != gReqId) return;
        gReqId = "";
        tell(av, "Configure your character on the HUD first.");
        return;
    }
    if (op == "ACTION") handleAction(body, speaker);
}

tellStatus(key av) {
    string text;
    string target;
    text = gName + "\nHP " + (string)gHP + "/" + (string)gMax + "\nState: " + stateLabel();
    if (av == llGetOwner()) {
        target = gForcedName;
        if (gForced == NULL_KEY) target = "automatic";
        text = text + "\nAttack " + (string)gAtk + "\nDefense " + (string)gDef;
        text = text + "\nParty: " + (string)llGetListLength(gPartyNames);
        text = text + "\nTarget: " + target;
        text = text + "\nBehavior: " + gAggro;
        if (gBuild != "") text = text + "\nBuild: " + gBuild;
    }
    tell(av, text);
}

openRoot(key av) {
    list buttons;
    string info;
    integer ally;
    ally = isAllyKey(av);
    info = gName + "\nHP " + (string)gHP + "/" + (string)gMax + "\n" + stateLabel();
    if (gState == ST_OFF && !gResting) {
        info = info + "\nThe NPC is not active.";
        buttons = ["Status"];
    }
    else if (ally) buttons = ["Heal", "Status"];
    else {
        if (canStealth()) buttons = ["Attack", "Stealth", "Status"];
        else buttons = ["Attack", "Status"];
    }
    if (av == llGetOwner()) buttons = buttons + ["Manage"];
    sendShow(MENU_ROOT, av, info, buttons);
}

openManage(key av) {
    if (av != llGetOwner()) return;
    sendShow(MENU_MANAGE, av, "Manage " + gName + ".\nThese actions are not combat rules.", ["Set HP", "Set Attack", "Set Defense", "Set Name", "Set Party", "Set Target", "ON", "OFF", "Reload", "Back"]);
}

clearRuntimeKeys() {
    llLinksetDataDelete("n.set");
    llLinksetDataDelete("n.name");
    llLinksetDataDelete("n.max");
    llLinksetDataDelete("n.hp");
    llLinksetDataDelete("n.atk");
    llLinksetDataDelete("n.def");
    llLinksetDataDelete("n.state");
    llLinksetDataDelete("n.resting");
    llLinksetDataDelete("n.target");
    llLinksetDataDelete("n.targetname");
    llLinksetDataDelete("n.partyset");
    llLinksetDataDelete("n.party");
}

handleMenu(integer menu, key av, string message) {
    if (message == " ") return;
    if (menu == MENU_MANAGE) {
        if (av != llGetOwner()) return;
        if (message == "Set HP") sendBox(TEXT_HP, av, "Set HP for " + gName + ". Current " + (string)gHP + "/" + (string)gMax + ".");
        else if (message == "Set Attack") sendBox(TEXT_ATK, av, "Set Attack. Current " + (string)gAtk + ".");
        else if (message == "Set Defense") sendBox(TEXT_DEF, av, "Set Defense. Current " + (string)gDef + ".");
        else if (message == "Set Name") sendBox(TEXT_NAME, av, "Set the NPC name.");
        else if (message == "Set Party") sendBox(TEXT_PARTY, av, "Allies, separated by commas.\nSend clear to remove every ally.\nExample: isabela.evergarden, tisga.resident");
        else if (message == "Set Target") sendBox(TEXT_TARGET, av, "Avatar name or UUID.\nSend clear for automatic targeting.");
        else if (message == "ON") activate(gState, av);
        else if (message == "OFF") turnOff(av);
        else if (message == "Reload") {
            clearRuntimeKeys();
            llOwnerSay("Reloading configuration.");
            llMessageLinked(LINK_SET, LINK_BODY, "RST", NULL_KEY);
            llResetScript();
        }
        else if (message == "Back") openRoot(av);
        return;
    }
    if (message == "Attack") {
        if (!inRangeOf(av)) rangeFail(av);
        else beginQuery(av, "ATTACK");
    }
    else if (message == "Stealth") {
        if (!inRangeOf(av)) rangeFail(av);
        else if (!canStealth()) tell(av, "Stealth is not available.");
        else beginQuery(av, "STEALTH");
    }
    else if (message == "Heal") {
        if (!inRangeOf(av)) rangeFail(av);
        else beginQuery(av, "HEAL");
    }
    else if (message == "Status") tellStatus(av);
    else if (message == "Manage") openManage(av);
}

integer isUInt(string value) {
    integer i;
    integer n;
    string ch;
    value = llStringTrim(value, STRING_TRIM);
    n = llStringLength(value);
    if (n == 0) return FALSE;
    for (i = 0; i < n; i += 1) {
        ch = llGetSubString(value, i, i);
        if (llSubStringIndex("0123456789", ch) == -1) return FALSE;
    }
    return TRUE;
}

addParty(string raw) {
    string name;
    name = llToLower(llStringTrim(raw, STRING_TRIM));
    if (name == "" || llGetSubString(name, 0, 0) == "#") return;
    if (llListFindList(gPartyNames, [name]) != -1) return;
    if (llGetListLength(gPartyNames) >= 20) {
        llOwnerSay("Party is limited to 20 names.");
        return;
    }
    gPartyNames = gPartyNames + [name];
    if (llStringLength(name) == 36 && llGetSubString(name, 8, 8) == "-") {
        if (llListFindList(gPartyKeys, [(key)name]) == -1) gPartyKeys = gPartyKeys + [(key)name];
        return;
    }
    gJobs = gJobs + ["UK|" + name];
}

setPartyText(string raw) {
    list names;
    integer i;
    integer n;
    gPartyNames = [];
    gPartyKeys = [];
    if (llToLower(llStringTrim(raw, STRING_TRIM)) != "clear") {
        names = llParseString2List(raw, [","], []);
        n = llGetListLength(names);
        for (i = 0; i < n; i += 1) addParty(llList2String(names, i));
    }
    saveRuntime();
    tell(llGetOwner(), "Party updated.");
    pump();
}

setTargetText(string raw) {
    string name;
    name = llStringTrim(raw, STRING_TRIM);
    if (llToLower(name) == "clear" || name == "-" || name == "") {
        gForced = NULL_KEY;
        gForcedName = "";
        saveRuntime();
        tell(llGetOwner(), "Target cleared. The NPC will choose automatically.");
        return;
    }
    if (llStringLength(name) == 36 && llGetSubString(name, 8, 8) == "-") {
        gForced = (key)name;
        gForcedName = llToLower(name);
        saveRuntime();
        tell(llGetOwner(), "Target set.");
        return;
    }
    gJobs = gJobs + ["TG|" + name];
    pump();
}

handleText(integer which, key av, string message) {
    integer value;
    if (av != llGetOwner()) return;
    message = llStringTrim(message, STRING_TRIM);
    if (which == TEXT_HP || which == TEXT_ATK || which == TEXT_DEF) {
        if (!isUInt(message)) {
            tell(av, "Enter a whole number.");
            return;
        }
        value = (integer)message;
        if (which == TEXT_HP) setNpcHp(value);
        else if (which == TEXT_ATK) {
            if (value > 100000) value = 100000;
            gAtk = value;
            saveRuntime();
        }
        else {
            if (value > 100000) value = 100000;
            gDef = value;
            saveRuntime();
        }
        tell(av, gName + " — HP " + (string)gHP + "/" + (string)gMax + ", Attack " + (string)gAtk + ", Defense " + (string)gDef + ".");
        refreshText();
        return;
    }
    if (which == TEXT_NAME) {
        if (message == "") return;
        gName = sanitize(message);
        if (gName == "") return;
        saveRuntime();
        refreshText();
        tell(av, "Name set to " + gName + ".");
        return;
    }
    if (which == TEXT_PARTY) setPartyText(message);
    else if (which == TEXT_TARGET) setTargetText(message);
}

parseLine(string raw) {
    string line;
    integer eq;
    string keyName;
    string value;
    integer number;
    line = llDumpList2String(llParseString2List(raw, ["\r"], []), "");
    line = llStringTrim(line, STRING_TRIM);
    if (line == "") return;
    if (llGetSubString(line, 0, 0) == "#") return;
    if (gMode == 2) {
        if (llLinksetDataRead("n.partyset") == "1") return;
        addParty(line);
        return;
    }
    eq = llSubStringIndex(line, "=");
    if (eq < 1) return;
    keyName = llToLower(llStringTrim(llGetSubString(line, 0, eq - 1), STRING_TRIM));
    value = llStringTrim(llGetSubString(line, eq + 1, -1), STRING_TRIM);
    if (gMode == 0) {
        number = (integer)value;
        if (keyName == "range") {
            gRangeM = number;
            if (gRangeM < 1) gRangeM = 1;
            if (gRangeM > 10) {
                gRangeM = 10;
                if (!gWarnedRange) {
                    gWarnedRange = TRUE;
                    llOwnerSay("Attack range is capped at 10m.");
                }
            }
        }
        llMessageLinked(LINK_SET, LINK_BODY, "D\n" + keyName + "\n" + (string)number, NULL_KEY);
        return;
    }
    if (keyName == "name") gNameT = sanitize(value);
    else if (keyName == "hp") gHpT = (integer)value;
    else if (keyName == "attack") gAtkT = (integer)value;
    else if (keyName == "defense") gDefT = (integer)value;
    else if (keyName == "rest_seconds") {
        gRest = (integer)value;
        if (gRest < 0) gRest = 0;
        if (gRest > 86400) gRest = 86400;
    }
    else if (keyName == "restore_hp") {
        if (value == "no" || value == "defeated" || value == "always") gRestore = value;
    }
    else if (keyName == "aggro") {
        if (value == "on_sight" || value == "on_attack") gAggro = value;
    }
    else if (keyName == "combat_timeout") {
        gCombatTimeout = (integer)value;
        if (gCombatTimeout < 0) gCombatTimeout = 0;
    }
    else if (keyName == "scan_seconds") {
        gScanEvery = (integer)value;
        if (gScanEvery < 2) gScanEvery = 2;
    }
}

commitCard() {
    if (gMode == 1) {
        if (gNameT != "") gName = gNameT;
        if (gHpT >= 0) {
            if (gHpT < 1) {
                gMax = 1;
                gHP = 0;
                gState = ST_DEFEATED;
            }
            else {
                gMax = gHpT;
                gHP = gHpT;
            }
        }
        if (gAtkT >= 0) gAtk = gAtkT;
        if (gDefT >= 0) gDef = gDefT;
        if (gMax < 1) gMax = 1;
        if (gHP > gMax) gHP = gMax;
    }
}

applyRuntime() {
    string party;
    list names;
    integer i;
    integer n;
    if (llLinksetDataRead("n.set") != "1") return;
    if (llLinksetDataRead("n.name") != "") gName = llLinksetDataRead("n.name");
    if (llLinksetDataRead("n.max") != "") gMax = (integer)llLinksetDataRead("n.max");
    if (llLinksetDataRead("n.hp") != "") gHP = (integer)llLinksetDataRead("n.hp");
    if (llLinksetDataRead("n.atk") != "") gAtk = (integer)llLinksetDataRead("n.atk");
    if (llLinksetDataRead("n.def") != "") gDef = (integer)llLinksetDataRead("n.def");
    if (llLinksetDataRead("n.state") != "") gState = (integer)llLinksetDataRead("n.state");
    gResting = (integer)llLinksetDataRead("n.resting");
    gForced = (key)llLinksetDataRead("n.target");
    gForcedName = llLinksetDataRead("n.targetname");
    if (gMax < 1) gMax = 1;
    if (gHP < 0) gHP = 0;
    if (gHP > gMax) gHP = gMax;
    if (gAtk < 0) gAtk = 0;
    if (gDef < 0) gDef = 0;
    if (gState < ST_OFF || gState > ST_DEFEATED) gState = ST_OFF;
    if (llLinksetDataRead("n.partyset") == "1") {
        gPartyNames = [];
        gPartyKeys = [];
        party = llLinksetDataRead("n.party");
        names = llParseString2List(party, [","], []);
        n = llGetListLength(names);
        for (i = 0; i < n; i += 1) addParty(llList2String(names, i));
    }
}

finishBoot() {
    if (gBooted) return;
    if (!gDidOverride) {
        gDidOverride = TRUE;
        applyRuntime();
        if (llGetListLength(gJobs) != 0) {
            pump();
            return;
        }
    }
    gBooted = TRUE;
    gReady = TRUE;
    if (gLastActivity == 0) gLastActivity = llGetUnixTime();
    refreshText();
    pushListen();
    armTimer();
    llOwnerSay(gName + " is ready. State: " + stateLabel() + ". Touch the NPC and choose ON.");
}

pump() {
    string job;
    integer bar;
    string kind;
    string arg;
    if (gQuery != NULL_KEY) return;
    if (llGetListLength(gJobs) == 0) {
        finishBoot();
        return;
    }
    job = llList2String(gJobs, 0);
    gJobs = llDeleteSubList(gJobs, 0, 0);
    bar = llSubStringIndex(job, "|");
    if (bar < 1) {
        pump();
        return;
    }
    kind = llGetSubString(job, 0, bar - 1);
    arg = llGetSubString(job, bar + 1, -1);
    if (kind == "UK" || kind == "TG") {
        gPendingName = arg;
        gQueryKind = kind;
        gQuery = llRequestUserKey(arg);
        return;
    }
    pump();
}

applyZ(string body) {
    list fields;
    string kind;
    key av;
    integer newHp;
    integer stealth;
    integer failed;
    integer damage;
    fields = llParseStringKeepNulls(body, ["|"], []);
    kind = llList2String(fields, 1);
    av = (key)llList2String(fields, 2);
    if (kind == "ATTACK") {
        newHp = (integer)llList2String(fields, 3);
        stealth = (integer)llList2String(fields, 4);
        failed = (integer)llList2String(fields, 5);
        if (newHp < 0) newHp = 0;
        gHP = newHp;
        if (failed) {
            enter(ST_COMBAT);
            startCounter();
            ack(av);
            return;
        }
        if (gHP <= 0) enter(ST_DEFEATED);
        else enter(ST_COMBAT);
        if (gHP > 0 && !stealth) startCounter();
        ack(av);
        return;
    }
    if (kind == "HEAL") {
        newHp = (integer)llList2String(fields, 3);
        if (newHp < 0) newHp = 0;
        gHP = newHp;
        if (gState == ST_DEFEATED) {
            if (gAggro == "on_sight") enter(ST_ACTIVE);
            else enter(ST_IDLE);
        }
        else {
            refreshText();
            saveRuntime();
        }
        ack(av);
        return;
    }
    if (kind == "COUNTER") {
        newHp = (integer)llList2String(fields, 3);
        damage = (integer)llList2String(fields, 4);
        if (newHp < 0) newHp = 0;
        remember(av, newHp);
        enter(ST_COMBAT);
        if (damage > 0) llMessageLinked(LINK_SET, LINK_SEND, "HPDELTA|" + (string)av + "|" + (string)(-damage), av);
        ack(av);
    }
}

onTouch(string rest) {
    key av;
    av = (key)rest;
    if (!gReady) {
        tell(av, "The NPC is still starting.");
        return;
    }
    gLastActivity = llGetUnixTime();
    if (gState == ST_OFF && gResting) activate(ST_OFF, av);
    openRoot(av);
}

onCard(string name) {
    gCard = name;
    gHpT = -1;
    gAtkT = -1;
    gDefT = -1;
    gNameT = "";
    gMode = -1;
    if (name == "combat") gMode = 0;
    else if (name == "npc") gMode = 1;
    else if (name == "party") gMode = 2;
}

onDo(string rest) {
    integer cut;
    integer menu;
    key av;
    string message;
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    menu = (integer)llGetSubString(rest, 0, cut - 1);
    rest = llGetSubString(rest, cut + 1, -1);
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    av = (key)llGetSubString(rest, 0, cut - 1);
    message = llGetSubString(rest, cut + 1, -1);
    handleMenu(menu, av, message);
}

onText(string rest) {
    integer cut;
    integer which;
    key av;
    string message;
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    which = (integer)llGetSubString(rest, 0, cut - 1);
    rest = llGetSubString(rest, cut + 1, -1);
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    av = (key)llGetSubString(rest, 0, cut - 1);
    message = llGetSubString(rest, cut + 1, -1);
    handleText(which, av, message);
}

onBody(string body) {
    string op;
    op = opOf(body);
    if (op == "C") onCard(restOf(body));
    else if (op == "L") parseLine(restOf(body));
    else if (op == "E") commitCard();
    else if (op == "BOOT") finishBoot();
    else if (op == "TOUCH") onTouch(restOf(body));
    else if (op == "DO") onDo(restOf(body));
    else if (op == "TXT") onText(restOf(body));
    else if (op == "Z") applyZ(body);
    else if (op == "RST") llResetScript();
}

default {
    state_entry() {
        gRangeM = 10;
        gRest = 300;
        gRestore = "defeated";
        gAggro = "on_attack";
        gCombatTimeout = 40;
        gScanEvery = 6;
        gName = llGetObjectName();
        gMax = 30;
        gHP = 30;
        gAtk = 4;
        gDef = 2;
        gState = ST_OFF;
        gQuery = NULL_KEY;
        gForced = NULL_KEY;
        llSetText(gName + "\nStarting", <0.7, 0.7, 0.7>, 1.0);
    }

    on_rez(integer start) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) {
            clearRuntimeKeys();
            llResetScript();
        }
        if (change & CHANGED_INVENTORY) llResetScript();
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_READY) {
            gBuild = str;
            if (gReady) pushListen();
        }
        else if (num == LINK_RECV) onRecv(str, id);
        else if (num == LINK_BODY) onBody(str);
    }

    dataserver(key query, string data) {
        if (query != gQuery) return;
        gQuery = NULL_KEY;
        if (gQueryKind == "UK") {
            if ((key)data != NULL_KEY) {
                if (llListFindList(gPartyKeys, [(key)data]) == -1) gPartyKeys = gPartyKeys + [(key)data];
            }
            else llOwnerSay("Could not resolve avatar: " + gPendingName);
            pump();
            return;
        }
        if (gQueryKind == "TG") {
            if ((key)data != NULL_KEY) {
                gForced = (key)data;
                gForcedName = gPendingName;
                saveRuntime();
                tell(llGetOwner(), "Target set to " + gPendingName + ".");
            }
            else tell(llGetOwner(), "Could not resolve avatar: " + gPendingName);
            pump();
            return;
        }
        pump();
    }

    sensor(integer detected) {
        integer i;
        key pick;
        key av;
        gSensorBusy = FALSE;
        pick = NULL_KEY;
        for (i = 0; i < detected; i += 1) {
            av = llDetectedKey(i);
            if (pick == NULL_KEY && validFoeKey(av)) pick = av;
        }
        gSense = "";
        if (pick == NULL_KEY) return;
        if (gState == ST_ACTIVE || gState == ST_IDLE) enter(ST_COMBAT);
        beginQuery(pick, "COUNTER");
    }

    no_sensor() {
        gSensorBusy = FALSE;
        gSense = "";
    }

    timer() {
        integer now;
        now = llGetUnixTime();
        if (gReqId != "" && now - gReqTime > 8) {
            if (gReqAv != NULL_KEY && gReqKind != "COUNTER") {
                tell(gReqAv, "No SL RPG Combat HUD detected.");
                tell(gReqAv, "Wear the HUD to take this action.");
            }
            gReqId = "";
        }
        if (!gReady) return;
        if (gState == ST_OFF) {
            pushListen();
            return;
        }
        if (gState == ST_COMBAT && gCombatTimeout > 0 && now - gLastActivity >= gCombatTimeout) {
            gLastActivity = now;
            if (gAggro == "on_sight") enter(ST_ACTIVE);
            else enter(ST_IDLE);
            return;
        }
        if ((gState == ST_IDLE || gState == ST_ACTIVE) && gRest > 0 && now - gLastActivity >= gRest) {
            autoRest();
            return;
        }
        if (gState == ST_ACTIVE && gAggro == "on_sight" && now - gLastScan >= gScanEvery) {
            gLastScan = now;
            startCounter();
        }
    }
}
