// SL RPG Combat — NPC menus and notecard pump.
// Put this in the NPC root prim with sl_rpg_auth, sl_rpg_npc, and sl_rpg_npc_fight.
// Save every script with the Mono compiler checked.
// Touch and dialogs live only in this script. User-facing text is English.

integer LINK_BODY = 51011;

integer MENU_ROOT = 1;
integer MENU_MANAGE = 2;

integer gHandle;
integer gChan;
integer gMenu;
integer gText;
integer gExpires;
key gMenuAv;

list gJobs;
key gQuery;
string gCard;
integer gLine;
integer gBootSent;

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
    llSetTimerEvent(0.0);
}

dialogTo(key av, string prompt, list labels) {
    if (av == NULL_KEY) return;
    if (llGetListLength(labels) == 0) labels = ["Status"];
    if (gHandle) llListenRemove(gHandle);
    gChan = -((integer)llFrand(1000000000.0) + 100000);
    gHandle = llListen(gChan, "", av, "");
    gMenuAv = av;
    gExpires = llGetUnixTime() + 45;
    llSetTimerEvent(1.0);
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
    llSetTimerEvent(1.0);
    if (llStringLength(prompt) > 480) prompt = llGetSubString(prompt, 0, 479);
    llTextBox(av, prompt, gChan);
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

queueCard(string name) {
    if (llGetInventoryType(name) == INVENTORY_NOTECARD) gJobs = gJobs + ["NC|" + name];
}

pump() {
    string job;
    integer bar;
    string kind;
    string arg;
    if (gQuery != NULL_KEY) return;
    if (llGetListLength(gJobs) == 0) {
        if (gBootSent) return;
        gBootSent = TRUE;
        llMessageLinked(LINK_SET, LINK_BODY, "BOOT", NULL_KEY);
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
    if (kind != "NC" || llGetInventoryType(arg) != INVENTORY_NOTECARD) {
        pump();
        return;
    }
    gCard = arg;
    gLine = 0;
    llMessageLinked(LINK_SET, LINK_BODY, "C\n" + arg, NULL_KEY);
    gQuery = llGetNotecardLine(gCard, 0);
}

onShow(string rest) {
    integer cut;
    string menuS;
    string avS;
    string buttons;
    string prompt;
    list labels;
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    menuS = llGetSubString(rest, 0, cut - 1);
    rest = llGetSubString(rest, cut + 1, -1);
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    avS = llGetSubString(rest, 0, cut - 1);
    rest = llGetSubString(rest, cut + 1, -1);
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    buttons = llGetSubString(rest, 0, cut - 1);
    prompt = llGetSubString(rest, cut + 1, -1);
    gMenu = (integer)menuS;
    gText = 0;
    labels = llParseString2List(buttons, ["|"], []);
    dialogTo((key)avS, prompt, labels);
}

onBox(string rest) {
    integer cut;
    string textS;
    string avS;
    string prompt;
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    textS = llGetSubString(rest, 0, cut - 1);
    rest = llGetSubString(rest, cut + 1, -1);
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    avS = llGetSubString(rest, 0, cut - 1);
    prompt = llGetSubString(rest, cut + 1, -1);
    gText = (integer)textS;
    textBoxTo((key)avS, prompt);
}

onBody(string body) {
    string op;
    op = opOf(body);
    if (op == "SHOW") onShow(restOf(body));
    else if (op == "BOX") onBox(restOf(body));
    else if (op == "RST") llResetScript();
}

default {
    state_entry() {
        gQuery = NULL_KEY;
        queueCard("npc");
        queueCard("combat");
        queueCard("party");
        if (llGetInventoryType("npc") != INVENTORY_NOTECARD) llOwnerSay("Notecard \"npc\" is missing. Using default statistics.");
        if (llGetInventoryType("combat") != INVENTORY_NOTECARD) llOwnerSay("Notecard \"combat\" is missing. Using the default combat rules.");
        if (llGetInventoryType("party") != INVENTORY_NOTECARD) llOwnerSay("Notecard \"party\" is missing. This NPC has no allies.");
        pump();
    }

    on_rez(integer start) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) llResetScript();
        if (change & CHANGED_INVENTORY) llResetScript();
    }

    touch_start(integer total) {
        key av;
        av = llDetectedKey(0);
        llMessageLinked(LINK_SET, LINK_BODY, "TOUCH\n" + (string)av, av);
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_BODY) onBody(str);
    }

    dataserver(key query, string data) {
        if (query != gQuery) return;
        if (data == EOF) {
            gQuery = NULL_KEY;
            llMessageLinked(LINK_SET, LINK_BODY, "E\n" + gCard, NULL_KEY);
            pump();
            return;
        }
        llMessageLinked(LINK_SET, LINK_BODY, "L\n" + data, NULL_KEY);
        gLine = gLine + 1;
        gQuery = llGetNotecardLine(gCard, gLine);
    }

    listen(integer channel, string name, key id, string message) {
        integer menu;
        integer text;
        if (channel != gChan) return;
        if (id != gMenuAv) return;
        menu = gMenu;
        text = gText;
        if (text != 0) {
            gText = 0;
            llMessageLinked(LINK_SET, LINK_BODY, "TXT\n" + (string)text + "\n" + (string)id + "\n" + message, id);
            return;
        }
        llMessageLinked(LINK_SET, LINK_BODY, "DO\n" + (string)menu + "\n" + (string)id + "\n" + message, id);
    }

    timer() {
        if (gHandle && llGetUnixTime() > gExpires) closeDialog();
    }
}
