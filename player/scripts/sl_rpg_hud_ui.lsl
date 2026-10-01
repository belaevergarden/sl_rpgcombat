// SL RPG Combat — HUD menus.
// Put this in the HUD root prim with sl_rpg_auth, sl_rpg_hud, and
// sl_rpg_hud_cards. Save every script with the Mono compiler checked.
// Touch and dialogs live only in this script. User-facing text is English.

integer LINK_SEND = 51001;
integer LINK_LISTEN = 51003;
integer LINK_BODY = 51011;

integer MENU_INTRO = 1;
integer MENU_GENDER = 2;
integer MENU_RACE = 3;
integer MENU_CLASS = 4;
integer MENU_CONFIRM = 5;
integer MENU_MAIN = 6;
integer MENU_ROLL = 7;
integer MENU_CONFIG = 8;
integer MENU_HP = 9;

integer TEXT_NAME = 1;
integer TEXT_GENDER = 2;
integer TEXT_RACE = 3;
integer TEXT_CLASS = 4;
integer TEXT_HP = 5;
integer TEXT_ATK = 6;
integer TEXT_DEF = 7;
integer TEXT_SET_HP = 8;

integer gReadyChar;
integer gCustom;
integer gCardsDone;
integer gFromConfig;
string gName;
string gGender;
string gRace;
string gClass;
string gGPretty;
string gRPretty;
string gCPretty;
integer gHP;
integer gMax;
integer gAtk;
integer gDef;
integer gDefending;
integer gRangeM;
integer gDefendBonus;

list gGId;
list gGName;
list gGHp;
list gGAtk;
list gGDef;
list gRId;
list gRName;
list gRHp;
list gRAtk;
list gRDef;
list gCId;
list gCName;
list gCHp;
list gCAtk;
list gCDef;

integer gMenu;
integer gText;
integer gPage;
integer gPickG;
integer gPickR;
integer gPickC;
integer gChan;
integer gHandle;
integer gExpires;
integer gWizard;
key gTarget;
string gTargetName;

string sanitize(string value) {
    value = llDumpList2String(llParseString2List(value, ["|", "\n", "\r"], []), " ");
    value = llStringTrim(value, STRING_TRIM);
    if (llStringLength(value) > 40) value = llGetSubString(value, 0, 39);
    return value;
}

string defaultName() {
    string n;
    n = llGetDisplayName(llGetOwner());
    if (n == "") n = llGetUsername(llGetOwner());
    if (n == "") n = "Adventurer";
    return sanitize(n);
}

string titleFromFile(string file, string prefix) {
    string rest;
    list words;
    list out;
    integer i;
    integer n;
    string word;
    rest = llDeleteSubString(file, 0, llStringLength(prefix) - 1);
    words = llParseString2List(llToLower(rest), ["_"], []);
    n = llGetListLength(words);
    for (i = 0; i < n; i += 1) {
        word = llList2String(words, i);
        if (llStringLength(word) > 0) {
            out = out + [llToUpper(llGetSubString(word, 0, 0)) + llDeleteSubString(word, 0, 0)];
        }
    }
    if (llGetListLength(out) == 0) return file;
    return llDumpList2String(out, " ");
}

string fitButton(string label) {
    if (label == "Prev" || label == "Next" || label == "Back" || label == " ") label = label + ".";
    if (llStringLength(label) > 24) label = llGetSubString(label, 0, 23);
    if (label == "") label = " ";
    return label;
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

string opOf(string body) {
    integer cut;
    cut = llSubStringIndex(body, "\n");
    if (cut < 0) cut = llSubStringIndex(body, "|");
    if (cut < 0) return body;
    return llGetSubString(body, 0, cut - 1);
}

pushStats() {
    llMessageLinked(LINK_SET, LINK_BODY, "STATS|" + (string)gReadyChar + "|" + (string)gHP + "|" + (string)gMax + "|" + (string)gAtk + "|" + (string)gDef + "|" + sanitize(gName), NULL_KEY);
}

closeUi() {
    if (gHandle) llListenRemove(gHandle);
    gHandle = 0;
    gText = 0;
    gMenu = 0;
    llSetTimerEvent(0.0);
}

dialog(string prompt, list labels) {
    if (llGetListLength(labels) == 0) labels = ["Back"];
    if (gHandle) llListenRemove(gHandle);
    gChan = -((integer)llFrand(1000000000.0) + 100000);
    gHandle = llListen(gChan, "", llGetOwner(), "");
    gExpires = llGetUnixTime() + 45;
    llSetTimerEvent(1.0);
    if (llStringLength(prompt) > 480) prompt = llGetSubString(prompt, 0, 479);
    llDialog(llGetOwner(), prompt, orderButtons(labels), gChan);
}

textBox(string prompt) {
    if (gHandle) llListenRemove(gHandle);
    gChan = -((integer)llFrand(1000000000.0) + 100000);
    gHandle = llListen(gChan, "", llGetOwner(), "");
    gExpires = llGetUnixTime() + 45;
    gMenu = 0;
    llSetTimerEvent(1.0);
    if (llStringLength(prompt) > 480) prompt = llGetSubString(prompt, 0, 479);
    llTextBox(llGetOwner(), prompt, gChan);
}

saveChar() {
    string custom;
    custom = "0";
    if (gCustom) custom = "1";
    llLinksetDataWrite("c.ready", "1");
    llLinksetDataWrite("c.name", gName);
    llLinksetDataWrite("c.gender", gGender);
    llLinksetDataWrite("c.race", gRace);
    llLinksetDataWrite("c.class", gClass);
    llLinksetDataWrite("c.gname", gGPretty);
    llLinksetDataWrite("c.rname", gRPretty);
    llLinksetDataWrite("c.cname", gCPretty);
    llLinksetDataWrite("c.hp", (string)gHP);
    llLinksetDataWrite("c.max", (string)gMax);
    llLinksetDataWrite("c.atk", (string)gAtk);
    llLinksetDataWrite("c.def", (string)gDef);
    llLinksetDataWrite("c.custom", custom);
    pushStats();
}

clearStored() {
    llLinksetDataDelete("c.ready");
    llLinksetDataDelete("c.name");
    llLinksetDataDelete("c.gender");
    llLinksetDataDelete("c.race");
    llLinksetDataDelete("c.class");
    llLinksetDataDelete("c.gname");
    llLinksetDataDelete("c.rname");
    llLinksetDataDelete("c.cname");
    llLinksetDataDelete("c.hp");
    llLinksetDataDelete("c.max");
    llLinksetDataDelete("c.atk");
    llLinksetDataDelete("c.def");
    llLinksetDataDelete("c.custom");
}

loadChar() {
    if (llLinksetDataRead("c.ready") != "1") {
        gReadyChar = FALSE;
        gCustom = FALSE;
        gName = defaultName();
        return;
    }
    gReadyChar = TRUE;
    gName = llLinksetDataRead("c.name");
    gGender = llLinksetDataRead("c.gender");
    gRace = llLinksetDataRead("c.race");
    gClass = llLinksetDataRead("c.class");
    gGPretty = llLinksetDataRead("c.gname");
    gRPretty = llLinksetDataRead("c.rname");
    gCPretty = llLinksetDataRead("c.cname");
    gHP = (integer)llLinksetDataRead("c.hp");
    gMax = (integer)llLinksetDataRead("c.max");
    gAtk = (integer)llLinksetDataRead("c.atk");
    gDef = (integer)llLinksetDataRead("c.def");
    gCustom = llLinksetDataRead("c.custom") == "1";
    if (gName == "") gName = defaultName();
    if (gMax < 1) gMax = 1;
    if (gHP < 0) gHP = 0;
    if (gHP > gMax) gHP = gMax;
    if (gAtk < 0) gAtk = 0;
    if (gDef < 0) gDef = 0;
}

recompute() {
    integer gi;
    integer ri;
    integer ci;
    integer oldMax;
    integer wasFull;
    integer hp;
    integer atk;
    integer def;
    if (gCustom || !gReadyChar) return;
    gi = llListFindList(gGId, [gGender]);
    ri = llListFindList(gRId, [gRace]);
    ci = llListFindList(gCId, [gClass]);
    if (gi < 0 || ri < 0 || ci < 0) {
        llOwnerSay("A saved preset is missing from this HUD. Current statistics were kept.");
        return;
    }
    oldMax = gMax;
    wasFull = FALSE;
    if (gHP == oldMax) wasFull = TRUE;
    gGPretty = llList2String(gGName, gi);
    gRPretty = llList2String(gRName, ri);
    gCPretty = llList2String(gCName, ci);
    hp = llList2Integer(gGHp, gi) + llList2Integer(gRHp, ri) + llList2Integer(gCHp, ci);
    atk = llList2Integer(gGAtk, gi) + llList2Integer(gRAtk, ri) + llList2Integer(gCAtk, ci);
    def = llList2Integer(gGDef, gi) + llList2Integer(gRDef, ri) + llList2Integer(gCDef, ci);
    if (hp < 1) hp = 1;
    if (atk < 0) atk = 0;
    if (def < 0) def = 0;
    gMax = hp;
    gAtk = atk;
    gDef = def;
    if (wasFull || gHP > gMax || gHP < 0) gHP = gMax;
}

string summary() {
    string text;
    string target;
    text = gName + "\n" + gGPretty + " " + gRPretty + " " + gCPretty;
    text = text + "\nHP " + (string)gHP + "/" + (string)gMax;
    text = text + "\nAttack " + (string)gAtk + "    Defense " + (string)gDef;
    target = gTargetName;
    if (gTarget == NULL_KEY || target == "") target = "none";
    text = text + "\nTarget: " + target;
    if (gDefending) text = text + "\nDefending";
    return text;
}

sayRoll(integer sides) {
    integer result;
    string who;
    result = 1 + (integer)llFrand((float)sides);
    who = gName;
    if (who == "") who = defaultName();
    llSay(0, who + " rolls 1d" + (string)sides + " and gets " + (string)result + ".");
}

act(string kind) {
    llMessageLinked(LINK_SET, LINK_BODY, "ACT|" + kind, NULL_KEY);
}

openIntro() {
    gMenu = MENU_INTRO;
    gText = 0;
    dialog("Create your character.\nDice can be rolled before combat.", ["Presets", "Custom", "Roll"]);
}

openMain() {
    gMenu = MENU_MAIN;
    gText = 0;
    dialog(summary(), ["Attack", "Stealth", "Heal", "Roll", "Defend", "Config", "Set HP", "Status", "Clear"]);
}

openRoll() {
    gMenu = MENU_ROLL;
    gText = 0;
    dialog("Roll dice as " + gName + ".", ["1d20", "1d100", "Back"]);
}

openConfig() {
    gMenu = MENU_CONFIG;
    gText = 0;
    dialog("Character configuration.\nPresets can be changed at any time.", ["Presets", "Custom", "Name", "Reset", "Back"]);
}

openHp() {
    gMenu = MENU_HP;
    gText = 0;
    dialog("HP " + (string)gHP + "/" + (string)gMax, ["Full", "Set", "Back"]);
}

openPreset(integer kind) {
    list names;
    integer total;
    integer pages;
    integer start;
    integer i;
    integer per;
    list labels;
    string title;
    string label;
    per = 9;
    if (kind == MENU_GENDER) {
        names = gGName;
        title = "Choose a gender.";
    }
    else if (kind == MENU_RACE) {
        names = gRName;
        title = "Choose a race.";
    }
    else {
        names = gCName;
        title = "Choose a class.";
    }
    gMenu = kind;
    gText = 0;
    total = llGetListLength(names);
    if (total == 0) {
        dialog(title + "\nAdd a notecard such as gen_batata, race_dragon, or class_necromancer.", ["Back"]);
        return;
    }
    pages = (total + per - 1) / per;
    if (gPage < 0) gPage = 0;
    if (gPage >= pages) gPage = pages - 1;
    start = gPage * per;
    for (i = start; i < start + per && i < total; i += 1) {
        label = fitButton(llList2String(names, i));
        labels = labels + [label];
    }
    labels = labels + ["Prev", "Next", "Back"];
    dialog(title + "\nPage " + (string)(gPage + 1) + "/" + (string)pages, labels);
}

integer indexOfLabel(list names, string message) {
    integer i;
    integer n;
    n = llGetListLength(names);
    for (i = 0; i < n; i += 1) {
        if (fitButton(llList2String(names, i)) == message) return i;
    }
    return -1;
}

openConfirm() {
    integer hp;
    integer atk;
    integer def;
    string text;
    if (gPickG < 0 || gPickR < 0 || gPickC < 0) {
        openIntro();
        return;
    }
    hp = llList2Integer(gGHp, gPickG) + llList2Integer(gRHp, gPickR) + llList2Integer(gCHp, gPickC);
    atk = llList2Integer(gGAtk, gPickG) + llList2Integer(gRAtk, gPickR) + llList2Integer(gCAtk, gPickC);
    def = llList2Integer(gGDef, gPickG) + llList2Integer(gRDef, gPickR) + llList2Integer(gCDef, gPickC);
    if (hp < 1) hp = 1;
    if (atk < 0) atk = 0;
    if (def < 0) def = 0;
    text = llList2String(gGName, gPickG) + " " + llList2String(gRName, gPickR) + " " + llList2String(gCName, gPickC);
    text = text + "\nHP " + (string)hp + "\nAttack " + (string)atk + "\nDefense " + (string)def;
    text = text + "\nAccept this character?";
    gMenu = MENU_CONFIRM;
    gText = 0;
    dialog(text, ["Accept", "Restart", "Custom", "Back"]);
}

acceptPresets() {
    gCustom = FALSE;
    gReadyChar = TRUE;
    gGender = llList2String(gGId, gPickG);
    gRace = llList2String(gRId, gPickR);
    gClass = llList2String(gCId, gPickC);
    gName = defaultName();
    if (llLinksetDataRead("c.name") != "") gName = llLinksetDataRead("c.name");
    gHP = 0;
    gMax = 0;
    recompute();
    gHP = gMax;
    saveChar();
    llOwnerSay(gName + " — " + gGPretty + " " + gRPretty + " " + gCPretty + ". HP " + (string)gHP + ", Attack " + (string)gAtk + ", Defense " + (string)gDef + ".");
    openMain();
}

startCustom() {
    gWizard = TRUE;
    gText = TEXT_NAME;
    textBox("Character name. This name is used in chat.\nExample: " + defaultName());
}

resetCharacter() {
    clearStored();
    gReadyChar = FALSE;
    gCustom = FALSE;
    gGender = "";
    gRace = "";
    gClass = "";
    gGPretty = "";
    gRPretty = "";
    gCPretty = "";
    gHP = 0;
    gMax = 0;
    gAtk = 0;
    gDef = 0;
    gDefending = FALSE;
    gPickG = -1;
    gPickR = -1;
    gPickC = -1;
    gName = defaultName();
    gTarget = NULL_KEY;
    gTargetName = "";
    pushStats();
    llMessageLinked(LINK_SET, LINK_BODY, "DEF|0", NULL_KEY);
    llMessageLinked(LINK_SET, LINK_BODY, "CLR", NULL_KEY);
    llOwnerSay("Character cleared.");
    openIntro();
}

handlePresetClick(string message) {
    list names;
    integer index;
    integer pages;
    integer total;
    if (gMenu == MENU_GENDER) names = gGName;
    else if (gMenu == MENU_RACE) names = gRName;
    else names = gCName;
    total = llGetListLength(names);
    pages = 1;
    if (total > 0) pages = (total + 8) / 9;
    if (message == "Prev") {
        if (gPage > 0) gPage = gPage - 1;
        openPreset(gMenu);
        return;
    }
    if (message == "Next") {
        if (gPage < pages - 1) gPage = gPage + 1;
        openPreset(gMenu);
        return;
    }
    if (message == "Back") {
        if (gMenu == MENU_GENDER) {
            if (gFromConfig && gReadyChar) openConfig();
            else openIntro();
        }
        else if (gMenu == MENU_RACE) openPreset(MENU_GENDER);
        else openPreset(MENU_RACE);
        return;
    }
    index = indexOfLabel(names, message);
    if (index < 0) return;
    if (gMenu == MENU_GENDER) {
        gPickG = index;
        gPage = 0;
        openPreset(MENU_RACE);
    }
    else if (gMenu == MENU_RACE) {
        gPickR = index;
        gPage = 0;
        openPreset(MENU_CLASS);
    }
    else {
        gPickC = index;
        openConfirm();
    }
}

handleMenu(string message) {
    string bonus;
    if (message == " ") return;
    if (gMenu == MENU_INTRO) {
        if (message == "Presets") {
            if (llGetListLength(gGName) == 0 || llGetListLength(gRName) == 0 || llGetListLength(gCName) == 0) {
                llOwnerSay("Add at least one gen_, one race_, and one class_ notecard, or choose Custom.");
                openIntro();
                return;
            }
            gFromConfig = FALSE;
            gPage = 0;
            gPickG = -1;
            gPickR = -1;
            gPickC = -1;
            openPreset(MENU_GENDER);
        }
        else if (message == "Custom") startCustom();
        else if (message == "Roll") openRoll();
        return;
    }
    if (gMenu == MENU_GENDER || gMenu == MENU_RACE || gMenu == MENU_CLASS) {
        handlePresetClick(message);
        return;
    }
    if (gMenu == MENU_CONFIRM) {
        if (message == "Accept") acceptPresets();
        else if (message == "Restart") {
            gPage = 0;
            gPickG = -1;
            gPickR = -1;
            gPickC = -1;
            openPreset(MENU_GENDER);
        }
        else if (message == "Custom") startCustom();
        else if (message == "Back") openPreset(MENU_CLASS);
        return;
    }
    if (gMenu == MENU_ROLL) {
        if (message == "1d20") {
            sayRoll(20);
            openRoll();
        }
        else if (message == "1d100") {
            sayRoll(100);
            openRoll();
        }
        else if (message == "Back") {
            if (gReadyChar) openMain();
            else openIntro();
        }
        return;
    }
    if (gMenu == MENU_CONFIG) {
        if (message == "Presets") {
            if (llGetListLength(gGName) == 0 || llGetListLength(gRName) == 0 || llGetListLength(gCName) == 0) {
                llOwnerSay("Add at least one gen_, one race_, and one class_ notecard.");
                openConfig();
                return;
            }
            gFromConfig = TRUE;
            gPage = 0;
            openPreset(MENU_GENDER);
        }
        else if (message == "Custom") startCustom();
        else if (message == "Name") {
            gWizard = FALSE;
            gText = TEXT_NAME;
            gFromConfig = TRUE;
            textBox("Character name. This name is used in chat.");
        }
        else if (message == "Reset") resetCharacter();
        else if (message == "Back") openMain();
        return;
    }
    if (gMenu == MENU_HP) {
        if (message == "Full") {
            gHP = gMax;
            saveChar();
            llOwnerSay("Your HP is now " + (string)gHP + "/" + (string)gMax + ".");
            openMain();
        }
        else if (message == "Set") {
            gText = TEXT_SET_HP;
            textBox("Current HP is " + (string)gHP + "/" + (string)gMax + ". Send the new current HP.");
        }
        else if (message == "Back") openMain();
        return;
    }
    if (gMenu != MENU_MAIN) return;
    if (message == "Attack") {
        act("ATTACK");
        openMain();
    }
    else if (message == "Stealth") {
        act("STEALTH");
        openMain();
    }
    else if (message == "Heal") {
        act("HEAL");
        openMain();
    }
    else if (message == "Roll") openRoll();
    else if (message == "Defend") {
        if (gDefending) {
            gDefending = FALSE;
            llOwnerSay("You lower your guard.");
            llMessageLinked(LINK_SET, LINK_BODY, "DEF|0", NULL_KEY);
        }
        else {
            gDefending = TRUE;
            bonus = (string)gDefendBonus;
            if (gDefendBonus >= 0) bonus = "+" + bonus;
            llOwnerSay("You raise your guard. Defense " + bonus + " on the next attack against you.");
            llMessageLinked(LINK_SET, LINK_BODY, "DEF|1", NULL_KEY);
        }
        openMain();
    }
    else if (message == "Config") openConfig();
    else if (message == "Set HP") openHp();
    else if (message == "Status") {
        llOwnerSay(summary());
        openMain();
    }
    else if (message == "Clear") {
        gTarget = NULL_KEY;
        gTargetName = "";
        llMessageLinked(LINK_SET, LINK_BODY, "CLR", NULL_KEY);
        llOwnerSay("Target cleared.");
        openMain();
    }
}

finishCustom() {
    if (gName == "") gName = defaultName();
    if (gGPretty == "") gGPretty = "Custom";
    if (gRPretty == "") gRPretty = "Custom";
    if (gCPretty == "") gCPretty = "Custom";
    gWizard = FALSE;
    gCustom = TRUE;
    gReadyChar = TRUE;
    gGender = "";
    gRace = "";
    gClass = "";
    gHP = gMax;
    saveChar();
    llOwnerSay(gName + " — " + gGPretty + " " + gRPretty + " " + gCPretty + ". HP " + (string)gHP + ", Attack " + (string)gAtk + ", Defense " + (string)gDef + ".");
    openMain();
}

handleText(string message) {
    integer value;
    message = llStringTrim(message, STRING_TRIM);
    if (message == "" && gText != TEXT_NAME && gText != TEXT_GENDER && gText != TEXT_RACE && gText != TEXT_CLASS) {
        if (gReadyChar) openConfig();
        else openIntro();
        return;
    }
    if (gText == TEXT_SET_HP) {
        if (!isUInt(message)) {
            llOwnerSay("Enter a whole number from 0 to " + (string)gMax + ".");
            openHp();
            return;
        }
        value = (integer)message;
        if (value < 0 || value > gMax) {
            llOwnerSay("HP must be from 0 to " + (string)gMax + ".");
            openHp();
            return;
        }
        gHP = value;
        saveChar();
        llOwnerSay("Your HP is now " + (string)gHP + "/" + (string)gMax + ".");
        if (gHP == 0) llOwnerSay("You are at 0 HP.");
        openMain();
        return;
    }
    if (gText == TEXT_NAME) {
        if (!gWizard) {
            if (message == "") {
                openConfig();
                return;
            }
            gName = sanitize(message);
            saveChar();
            llOwnerSay("Name set to " + gName + ".");
            openConfig();
            return;
        }
        if (message == "") gName = defaultName();
        else gName = sanitize(message);
        gText = TEXT_GENDER;
        textBox("Gender label. This is text only.\nExample: Female");
        return;
    }
    if (gText == TEXT_GENDER) {
        gGPretty = sanitize(message);
        gText = TEXT_RACE;
        textBox("Race label.\nExample: Human");
        return;
    }
    if (gText == TEXT_RACE) {
        gRPretty = sanitize(message);
        gText = TEXT_CLASS;
        textBox("Class label.\nExample: Knight");
        return;
    }
    if (gText == TEXT_CLASS) {
        gCPretty = sanitize(message);
        gText = TEXT_HP;
        textBox("Maximum HP.\nExample: 100");
        return;
    }
    if (gText == TEXT_HP || gText == TEXT_ATK || gText == TEXT_DEF) {
        if (!isUInt(message)) {
            llOwnerSay("Enter a whole number.");
            if (gText == TEXT_HP) textBox("Maximum HP.\nExample: 100");
            else if (gText == TEXT_ATK) textBox("Attack.\nExample: 5");
            else textBox("Defense.\nExample: 2");
            return;
        }
        value = (integer)message;
        if (value > 100000) {
            llOwnerSay("The limit is 100000.");
            if (gText == TEXT_HP) textBox("Maximum HP.\nExample: 100");
            else if (gText == TEXT_ATK) textBox("Attack.\nExample: 5");
            else textBox("Defense.\nExample: 2");
            return;
        }
        if (gText == TEXT_HP) {
            if (value < 1) {
                llOwnerSay("HP must be at least 1.");
                textBox("Maximum HP.\nExample: 100");
                return;
            }
            gMax = value;
            gText = TEXT_ATK;
            textBox("Attack.\nExample: 5");
        }
        else if (gText == TEXT_ATK) {
            gAtk = value;
            gText = TEXT_DEF;
            textBox("Defense.\nExample: 2");
        }
        else {
            gDef = value;
            finishCustom();
        }
    }
}

addPreset(string body) {
    list fields;
    integer mode;
    string card;
    string pretty;
    integer hp;
    integer atk;
    integer def;
    fields = llParseStringKeepNulls(body, ["|"], []);
    mode = (integer)llList2String(fields, 1);
    card = llList2String(fields, 2);
    pretty = llList2String(fields, 3);
    hp = (integer)llList2String(fields, 4);
    atk = (integer)llList2String(fields, 5);
    def = (integer)llList2String(fields, 6);
    if (pretty == "") {
        if (mode == 1) pretty = titleFromFile(card, "gen_");
        else if (mode == 2) pretty = titleFromFile(card, "race_");
        else pretty = titleFromFile(card, "class_");
    }
    if (mode == 1) {
        gGId = gGId + [card];
        gGName = gGName + [pretty];
        gGHp = gGHp + [hp];
        gGAtk = gGAtk + [atk];
        gGDef = gGDef + [def];
    }
    else if (mode == 2) {
        gRId = gRId + [card];
        gRName = gRName + [pretty];
        gRHp = gRHp + [hp];
        gRAtk = gRAtk + [atk];
        gRDef = gRDef + [def];
    }
    else if (mode == 3) {
        gCId = gCId + [card];
        gCName = gCName + [pretty];
        gCHp = gCHp + [hp];
        gCAtk = gCAtk + [atk];
        gCDef = gCDef + [def];
    }
}

onRules(string body) {
    list fields;
    fields = llParseStringKeepNulls(body, ["|"], []);
    gRangeM = (integer)llList2String(fields, 1);
    gDefendBonus = (integer)llList2String(fields, 2);
}

onHp(string body) {
    list fields;
    fields = llParseStringKeepNulls(body, ["|"], []);
    gHP = (integer)llList2String(fields, 1);
    gMax = (integer)llList2String(fields, 2);
    if (gHP < 0) gHP = 0;
    if (gMax < 1) gMax = 1;
    if (gHP > gMax) gHP = gMax;
    llLinksetDataWrite("c.hp", (string)gHP);
    llLinksetDataWrite("c.max", (string)gMax);
}

onTarget(string body) {
    list fields;
    fields = llParseStringKeepNulls(body, ["|"], []);
    gTarget = (key)llList2String(fields, 1);
    gTargetName = llList2String(fields, 2);
}

finishCards() {
    if (gCardsDone) return;
    gCardsDone = TRUE;
    loadChar();
    if (gReadyChar && !gCustom) recompute();
    if (gReadyChar) saveChar();
    else pushStats();
    llMessageLinked(LINK_SET, LINK_LISTEN, "1", NULL_KEY);
    if (gReadyChar) llOwnerSay(gName + " is ready. HP " + (string)gHP + "/" + (string)gMax + ". Touch the HUD to open it.");
    else llOwnerSay("No character yet. Touch the HUD to create one.");
}

onBody(string body) {
    string op;
    op = opOf(body);
    if (op == "ADD") addPreset(body);
    else if (op == "DONE") finishCards();
    else if (op == "RULES") onRules(body);
    else if (op == "HP") onHp(body);
    else if (op == "TGT") onTarget(body);
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
        gPickG = -1;
        gPickR = -1;
        gPickC = -1;
        gTarget = NULL_KEY;
        gName = defaultName();
    }

    on_rez(integer start) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) {
            clearStored();
            llResetScript();
        }
        if (change & CHANGED_INVENTORY) llResetScript();
    }

    touch_start(integer total) {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (!gCardsDone) {
            llOwnerSay("The HUD is still reading configuration.");
            return;
        }
        if (!gReadyChar) openIntro();
        else openMain();
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_BODY) onBody(str);
    }

    listen(integer channel, string name, key id, string message) {
        if (channel != gChan) return;
        if (id != llGetOwner()) return;
        if (gText != 0) handleText(message);
        else handleMenu(message);
    }

    timer() {
        if (gHandle && llGetUnixTime() > gExpires) closeUi();
    }
}
