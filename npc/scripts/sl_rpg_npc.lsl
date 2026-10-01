// SL RPG Combat — NPC.
// The NPC needs this script, sl_rpg_auth, and the notecards npc, combat, and party.
// User-facing text is English.
// If you change this file, also change SEC_CHANNEL, SEC_PASSWORD, and
// SEC_BUILD in both copies of sl_rpg_auth.lsl.

integer LINK_SEND = 51001;
integer LINK_RECV = 51002;
integer LINK_LISTEN = 51003;
integer LINK_READY = 51004;

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
integer gAttackDie;
integer gDefenseDie;
integer gCritMargin;
integer gCritMult;
integer gDamageDie;
integer gDamageScale;
integer gMinDamage;
integer gHealDie;
integer gHealBonus;
integer gDefendBonus;
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

integer gHandle;
integer gChan;
integer gMenu;
integer gText;
integer gExpires;
key gMenuAv;

list gJobs;
key gQuery;
string gQueryKind;
string gCard;
integer gLine;
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
    if (gHandle) llSetTimerEvent(1.0);
    else if (gState == ST_OFF) llSetTimerEvent(60.0);
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

sayAs(string speaker, string text) {
    string old;
    old = llGetObjectName();
    if (llStringLength(speaker) > 63) speaker = llGetSubString(speaker, 0, 62);
    if (speaker == "") speaker = gName;
    llSetObjectName(speaker);
    llSay(0, text);
    llSetObjectName(old);
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

integer rollDie(integer sides) {
    if (sides < 1) sides = 1;
    if (sides > 1000) sides = 1000;
    return 1 + (integer)llFrand((float)sides);
}

list opposed(integer atkStat, integer defStat) {
    integer atkDie;
    integer defDie;
    integer atkTotal;
    integer defTotal;
    atkDie = rollDie(gAttackDie);
    defDie = rollDie(gDefenseDie);
    atkTotal = atkDie + atkStat;
    defTotal = defDie + defStat;
    return [atkTotal - defTotal, atkDie, atkTotal, defDie, defTotal];
}

list resolve(integer atkStat, integer defStat) {
    list roll;
    integer margin;
    integer damage;
    integer crit;
    integer scale;
    roll = opposed(atkStat, defStat);
    margin = llList2Integer(roll, 0);
    damage = 0;
    crit = FALSE;
    if (margin > 0) {
        scale = gDamageScale;
        if (scale < 1) scale = 1;
        damage = rollDie(gDamageDie) + margin / scale;
        if (damage < gMinDamage) damage = gMinDamage;
        if (margin >= gCritMargin) {
            crit = TRUE;
            if (gCritMult > 1) damage = damage * gCritMult;
        }
        if (damage > 1000000) damage = 1000000;
    }
    return [margin, damage, crit, llList2Integer(roll, 1), llList2Integer(roll, 2), llList2Integer(roll, 3), llList2Integer(roll, 4)];
}

sayRolls(string attacker, integer atkStat, integer atkDie, integer atkTotal, string defender, integer defStat, integer defDie, integer defTotal) {
    sayAs(attacker, attacker + " rolls 1d" + (string)gAttackDie + " (" + (string)atkDie + ") + " + (string)atkStat + " Attack = " + (string)atkTotal + ". " + defender + " rolls 1d" + (string)gDefenseDie + " (" + (string)defDie + ") + " + (string)defStat + " Defense = " + (string)defTotal + ".");
}

narrateResult(string attacker, string defender, integer margin, integer damage, integer crit, integer hp, integer maxHp) {
    if (margin <= 0) sayAs(defender, "Miss. " + defender + " defends.");
    else if (crit) sayAs(attacker, "Critical hit! " + attacker + " deals " + (string)damage + " damage to " + defender + ". (" + (string)hp + "/" + (string)maxHp + " HP)");
    else sayAs(attacker, "Hit! " + attacker + " deals " + (string)damage + " damage to " + defender + ". (" + (string)hp + "/" + (string)maxHp + " HP)");
}

list orderButtons(list buttons) {
    integer n;
    integer extra;
    integer p;
    integer start;
    list fixed;
    n = llGetListLength(buttons);
    extra = n % 3;
    if (extra != 0) {
        extra = 3 - extra;
        for (p = 0; p < extra; p += 1) buttons = buttons + [" "];
        n = n + extra;
    }
    start = n - 3;
    while (start >= 0) {
        fixed = fixed + llList2List(buttons, start, start + 2);
        start = start - 3;
    }
    return fixed;
}

closeDialog() {
    if (gHandle) llListenRemove(gHandle);
    gHandle = 0;
    gMenu = 0;
    gText = 0;
    armTimer();
}

dialogTo(key av, string prompt, list labels) {
    if (av == NULL_KEY) return;
    if (llGetListLength(labels) == 0) labels = ["Status"];
    if (gHandle) llListenRemove(gHandle);
    gChan = -((integer)llFrand(1000000000.0) + 100000);
    gHandle = llListen(gChan, "", av, "");
    gMenuAv = av;
    gExpires = llGetUnixTime() + 45;
    armTimer();
    if (llStringLength(prompt) > 480) prompt = llGetSubString(prompt, 0, 479);
    llDialog(av, prompt, orderButtons(labels), gChan);
}

textBoxTo(key av, string prompt) {
    if (av == NULL_KEY) return;
    if (gHandle) llListenRemove(gHandle);
    gChan = -((integer)llFrand(1000000000.0) + 100000);
    gHandle = llListen(gChan, "", av, "");
    gMenuAv = av;
    gMenu = 0;
    gExpires = llGetUnixTime() + 45;
    armTimer();
    if (llStringLength(prompt) > 480) prompt = llGetSubString(prompt, 0, 479);
    llTextBox(av, prompt, gChan);
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

applyNpcDamage(integer damage) {
    integer left;
    left = gHP - damage;
    if (left < 0) left = 0;
    gHP = left;
    if (gHP <= 0) enter(ST_DEFEATED);
    else enter(ST_COMBAT);
}

doCounter(key av, string player, integer playerDef, integer playerHp, integer playerMax, integer defending) {
    integer defStat;
    list roll;
    integer margin;
    integer damage;
    integer crit;
    integer atkDie;
    integer atkTotal;
    integer defDie;
    integer defTotal;
    integer newHp;
    string bonus;
    if (gState == ST_OFF || gState == ST_DEFEATED) return;
    if (player == "") player = "Someone";
    if (!validFoeKey(av)) return;
    if (playerHp <= 0) return;
    defStat = playerDef;
    if (defending) defStat = defStat + gDefendBonus;
    roll = resolve(gAtk, defStat);
    margin = llList2Integer(roll, 0);
    damage = llList2Integer(roll, 1);
    crit = llList2Integer(roll, 2);
    atkDie = llList2Integer(roll, 3);
    atkTotal = llList2Integer(roll, 4);
    defDie = llList2Integer(roll, 5);
    defTotal = llList2Integer(roll, 6);
    if (damage > playerHp) damage = playerHp;
    newHp = playerHp - damage;
    sayAs(gName, gName + " attacks " + player + ".");
    if (defending) {
        bonus = (string)gDefendBonus;
        if (gDefendBonus >= 0) bonus = "+" + bonus;
        sayAs(player, player + " is defending (" + bonus + " Defense).");
    }
    sayRolls(gName, gAtk, atkDie, atkTotal, player, defStat, defDie, defTotal);
    narrateResult(gName, player, margin, damage, crit, newHp, playerMax);
    remember(av, newHp);
    gLastActivity = llGetUnixTime();
    enter(ST_COMBAT);
    if (damage > 0) llMessageLinked(LINK_SET, LINK_SEND, "HPDELTA|" + (string)av + "|" + (string)(-damage), av);
}

doHeal(key av, string player) {
    integer amount;
    integer missing;
    if (player == "") player = "Someone";
    if (gState == ST_OFF) {
        tell(av, "The NPC is not active.");
        return;
    }
    if (!isAllyKey(av)) {
        tell(av, "You can only heal an ally.");
        return;
    }
    if (!inRangeOf(av)) {
        rangeFail(av);
        return;
    }
    if (gHP >= gMax) {
        tell(av, gName + " is already at full HP.");
        return;
    }
    amount = rollDie(gHealDie) + gHealBonus;
    if (amount < 1) amount = 1;
    missing = gMax - gHP;
    if (amount > missing) amount = missing;
    gHP = gHP + amount;
    gLastActivity = llGetUnixTime();
    gLastPlayerAct = llGetUnixTime();
    if (gState == ST_DEFEATED) {
        if (gAggro == "on_sight") enter(ST_ACTIVE);
        else enter(ST_IDLE);
    }
    else {
        refreshText();
        saveRuntime();
    }
    sayAs(player, player + " heals " + gName + " for " + (string)amount + ". (" + (string)gHP + "/" + (string)gMax + " HP)");
}

doPlayerAttack(key av, string player, integer atkStat, integer stealth) {
    list check;
    list roll;
    integer margin;
    integer damage;
    integer crit;
    integer atkDie;
    integer atkTotal;
    integer defDie;
    integer defTotal;
    integer newHp;
    if (player == "") player = "Someone";
    if (gState == ST_OFF) {
        tell(av, "The NPC is not active.");
        return;
    }
    if (isAllyKey(av)) {
        tell(av, "You cannot attack an ally.");
        return;
    }
    if (!inRangeOf(av)) {
        rangeFail(av);
        return;
    }
    if (gState == ST_DEFEATED) {
        tell(av, "The NPC is defeated.");
        return;
    }
    if (stealth) {
        if (!canStealth()) {
            tell(av, "Stealth is not available.");
            return;
        }
    }
    gLastActivity = llGetUnixTime();
    gLastPlayerAct = llGetUnixTime();
    if (stealth) {
        check = opposed(atkStat, gDef);
        margin = llList2Integer(check, 0);
        atkDie = llList2Integer(check, 1);
        atkTotal = llList2Integer(check, 2);
        defDie = llList2Integer(check, 3);
        defTotal = llList2Integer(check, 4);
        sayRolls(player, atkStat, atkDie, atkTotal, gName, gDef, defDie, defTotal);
        if (margin <= 0) {
            sayAs(player, "Stealth failed.");
            sayAs(gName, "The NPC has detected you.");
            enter(ST_COMBAT);
            startCounter();
            return;
        }
        sayAs(player, "Successful stealth attack.");
    }
    roll = resolve(atkStat, gDef);
    margin = llList2Integer(roll, 0);
    damage = llList2Integer(roll, 1);
    crit = llList2Integer(roll, 2);
    atkDie = llList2Integer(roll, 3);
    atkTotal = llList2Integer(roll, 4);
    defDie = llList2Integer(roll, 5);
    defTotal = llList2Integer(roll, 6);
    newHp = gHP - damage;
    if (newHp < 0) newHp = 0;
    if (!stealth) sayAs(player, player + " attacks " + gName + ".");
    sayRolls(player, atkStat, atkDie, atkTotal, gName, gDef, defDie, defTotal);
    narrateResult(player, gName, margin, damage, crit, newHp, gMax);
    applyNpcDamage(damage);
    if (gHP > 0 && !stealth) startCounter();
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
    if (kind == "COUNTER") doCounter(av, player, defStat, hp, maxHp, defending);
    else if (kind == "HEAL") doHeal(av, player);
    else if (kind == "STEALTH") doPlayerAttack(av, player, atkStat, TRUE);
    else if (kind == "ATTACK") doPlayerAttack(av, player, atkStat, FALSE);
    else {
        ack(av);
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
    gMenu = MENU_ROOT;
    dialogTo(av, info, buttons);
}

openManage(key av) {
    if (av != llGetOwner()) return;
    gMenu = MENU_MANAGE;
    dialogTo(av, "Manage " + gName + ".\nThese actions are not combat rules.", ["Set HP", "Set Attack", "Set Defense", "Set Name", "Set Party", "Set Target", "ON", "OFF", "Reload", "Back"]);
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

handleMenu(string message) {
    key av;
    av = gMenuAv;
    if (message == " ") return;
    if (gMenu == MENU_MANAGE) {
        if (av != llGetOwner()) return;
        if (message == "Set HP") {
            gText = TEXT_HP;
            textBoxTo(av, "Set HP for " + gName + ". Current " + (string)gHP + "/" + (string)gMax + ".");
        }
        else if (message == "Set Attack") {
            gText = TEXT_ATK;
            textBoxTo(av, "Set Attack. Current " + (string)gAtk + ".");
        }
        else if (message == "Set Defense") {
            gText = TEXT_DEF;
            textBoxTo(av, "Set Defense. Current " + (string)gDef + ".");
        }
        else if (message == "Set Name") {
            gText = TEXT_NAME;
            textBoxTo(av, "Set the NPC name.");
        }
        else if (message == "Set Party") {
            gText = TEXT_PARTY;
            textBoxTo(av, "Allies, separated by commas.\nSend clear to remove every ally.\nExample: isabela.evergarden, tisga.resident");
        }
        else if (message == "Set Target") {
            gText = TEXT_TARGET;
            textBoxTo(av, "Avatar name or UUID.\nSend clear for automatic targeting.");
        }
        else if (message == "ON") activate(gState, av);
        else if (message == "OFF") turnOff(av);
        else if (message == "Reload") {
            clearRuntimeKeys();
            llOwnerSay("Reloading configuration.");
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

handleText(string message) {
    integer value;
    if (gMenuAv != llGetOwner()) return;
    message = llStringTrim(message, STRING_TRIM);
    if (gText == TEXT_HP || gText == TEXT_ATK || gText == TEXT_DEF) {
        if (!isUInt(message)) {
            tell(gMenuAv, "Enter a whole number.");
            return;
        }
        value = (integer)message;
        if (gText == TEXT_HP) setNpcHp(value);
        else if (gText == TEXT_ATK) {
            if (value > 100000) value = 100000;
            gAtk = value;
            saveRuntime();
        }
        else {
            if (value > 100000) value = 100000;
            gDef = value;
            saveRuntime();
        }
        tell(gMenuAv, gName + " — HP " + (string)gHP + "/" + (string)gMax + ", Attack " + (string)gAtk + ", Defense " + (string)gDef + ".");
        refreshText();
        return;
    }
    if (gText == TEXT_NAME) {
        if (message == "") return;
        gName = sanitize(message);
        if (gName == "") return;
        saveRuntime();
        refreshText();
        tell(gMenuAv, "Name set to " + gName + ".");
        return;
    }
    if (gText == TEXT_PARTY) setPartyText(message);
    else if (gText == TEXT_TARGET) setTargetText(message);
}

queueCard(string name) {
    if (llGetInventoryType(name) == INVENTORY_NOTECARD) gJobs = gJobs + ["NC|" + name];
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
        else if (keyName == "attack_die") gAttackDie = number;
        else if (keyName == "defense_die") gDefenseDie = number;
        else if (keyName == "crit_margin") gCritMargin = number;
        else if (keyName == "crit_multiplier") gCritMult = number;
        else if (keyName == "damage_die") gDamageDie = number;
        else if (keyName == "damage_bonus_scale") gDamageScale = number;
        else if (keyName == "min_damage") gMinDamage = number;
        else if (keyName == "heal_die") gHealDie = number;
        else if (keyName == "heal_bonus") gHealBonus = number;
        else if (keyName == "defend_bonus") gDefendBonus = number;
        if (gAttackDie < 1) gAttackDie = 1;
        if (gDefenseDie < 1) gDefenseDie = 1;
        if (gDamageDie < 1) gDamageDie = 1;
        if (gHealDie < 1) gHealDie = 1;
        if (gDamageScale < 1) gDamageScale = 1;
        if (gCritMult < 1) gCritMult = 1;
        if (gMinDamage < 0) gMinDamage = 0;
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
    if (kind == "NC") {
        if (llGetInventoryType(arg) != INVENTORY_NOTECARD) {
            pump();
            return;
        }
        gCard = arg;
        gLine = 0;
        gMode = -1;
        gHpT = -1;
        gAtkT = -1;
        gDefT = -1;
        gNameT = "";
        if (arg == "combat") gMode = 0;
        else if (arg == "npc") gMode = 1;
        else if (arg == "party") gMode = 2;
        gQueryKind = "NC";
        gQuery = llGetNotecardLine(gCard, 0);
        return;
    }
    if (kind == "UK" || kind == "TG") {
        gPendingName = arg;
        gQueryKind = kind;
        gQuery = llRequestUserKey(arg);
    }
}

default {
    state_entry() {
        gRangeM = 10;
        gAttackDie = 20;
        gDefenseDie = 20;
        gCritMargin = 10;
        gCritMult = 2;
        gDamageDie = 6;
        gDamageScale = 2;
        gMinDamage = 1;
        gHealDie = 8;
        gHealBonus = 0;
        gDefendBonus = 2;
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
        queueCard("npc");
        queueCard("combat");
        queueCard("party");
        if (llGetInventoryType("npc") != INVENTORY_NOTECARD) llOwnerSay("Notecard \"npc\" is missing. Using default statistics.");
        if (llGetInventoryType("combat") != INVENTORY_NOTECARD) llOwnerSay("Notecard \"combat\" is missing. Using the default combat rules.");
        if (llGetInventoryType("party") != INVENTORY_NOTECARD) llOwnerSay("Notecard \"party\" is missing. This NPC has no allies.");
        llSetText(gName + "\nStarting", <0.7, 0.7, 0.7>, 1.0);
        pump();
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

    touch_start(integer total) {
        key av;
        av = llDetectedKey(0);
        if (!gReady) {
            tell(av, "The NPC is still starting.");
            return;
        }
        gLastActivity = llGetUnixTime();
        if (gState == ST_OFF && gResting) activate(ST_OFF, av);
        openRoot(av);
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_READY) {
            gBuild = str;
            if (gReady) pushListen();
        }
        else if (num == LINK_RECV) onRecv(str, id);
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
        if (data == EOF) {
            commitCard();
            pump();
            return;
        }
        parseLine(data);
        gLine = gLine + 1;
        gQuery = llGetNotecardLine(gCard, gLine);
    }

    listen(integer channel, string name, key id, string message) {
        if (channel != gChan) return;
        if (id != gMenuAv) return;
        if (gText != 0) handleText(message);
        else handleMenu(message);
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
        if (gHandle && now > gExpires) closeDialog();
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
