// SL RPG Combat — NPC dice.
// Put this in the NPC root prim with sl_rpg_auth, sl_rpg_npc, and sl_rpg_npc_ui.
// Save every script with the Mono compiler checked.
// The NPC rolls both sides. User-facing text is English.

integer LINK_BODY = 51011;

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
string gName;

string opOf(string body) {
    integer cut;
    cut = llSubStringIndex(body, "\n");
    if (cut < 0) cut = llSubStringIndex(body, "|");
    if (cut < 0) return body;
    return llGetSubString(body, 0, cut - 1);
}

applyDie(string keyName, integer number) {
    if (keyName == "attack_die") gAttackDie = number;
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

sayAs(string speaker, string text) {
    string old;
    old = llGetObjectName();
    if (llStringLength(speaker) > 63) speaker = llGetSubString(speaker, 0, 62);
    if (speaker == "") speaker = gName;
    llSetObjectName(speaker);
    llSay(0, text);
    llSetObjectName(old);
}

sayRolls(string attacker, integer atkStat, integer atkDie, integer atkTotal, string defender, integer defStat, integer defDie, integer defTotal) {
    sayAs(attacker, attacker + " rolls 1d" + (string)gAttackDie + " (" + (string)atkDie + ") + " + (string)atkStat + " Attack = " + (string)atkTotal + ". " + defender + " rolls 1d" + (string)gDefenseDie + " (" + (string)defDie + ") + " + (string)defStat + " Defense = " + (string)defTotal + ".");
}

narrateResult(string attacker, string defender, integer margin, integer damage, integer crit, integer hp, integer maxHp) {
    if (margin <= 0) sayAs(defender, "Miss. " + defender + " defends.");
    else if (crit) sayAs(attacker, "Critical hit! " + attacker + " deals " + (string)damage + " damage to " + defender + ". (" + (string)hp + "/" + (string)maxHp + " HP)");
    else sayAs(attacker, "Hit! " + attacker + " deals " + (string)damage + " damage to " + defender + ". (" + (string)hp + "/" + (string)maxHp + " HP)");
}

replyAttack(key av, integer newHp, integer stealth, integer failed) {
    llMessageLinked(LINK_SET, LINK_BODY, "Z|ATTACK|" + (string)av + "|" + (string)newHp + "|" + (string)stealth + "|" + (string)failed, NULL_KEY);
}

attackJob(key av, string player, integer atkStat, integer stealth, integer npcHp, integer npcMax, integer npcDef, string npcName) {
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
    gName = npcName;
    if (stealth) {
        check = opposed(atkStat, npcDef);
        margin = llList2Integer(check, 0);
        atkDie = llList2Integer(check, 1);
        atkTotal = llList2Integer(check, 2);
        defDie = llList2Integer(check, 3);
        defTotal = llList2Integer(check, 4);
        sayRolls(player, atkStat, atkDie, atkTotal, npcName, npcDef, defDie, defTotal);
        if (margin <= 0) {
            sayAs(player, "Stealth failed.");
            sayAs(npcName, "The NPC has detected you.");
            replyAttack(av, npcHp, 1, 1);
            return;
        }
        sayAs(player, "Successful stealth attack.");
    }
    roll = resolve(atkStat, npcDef);
    margin = llList2Integer(roll, 0);
    damage = llList2Integer(roll, 1);
    crit = llList2Integer(roll, 2);
    atkDie = llList2Integer(roll, 3);
    atkTotal = llList2Integer(roll, 4);
    defDie = llList2Integer(roll, 5);
    defTotal = llList2Integer(roll, 6);
    newHp = npcHp - damage;
    if (newHp < 0) newHp = 0;
    if (!stealth) sayAs(player, player + " attacks " + npcName + ".");
    sayRolls(player, atkStat, atkDie, atkTotal, npcName, npcDef, defDie, defTotal);
    narrateResult(player, npcName, margin, damage, crit, newHp, npcMax);
    replyAttack(av, newHp, stealth, 0);
}

healJob(key av, string player, integer npcHp, integer npcMax, string npcName) {
    integer amount;
    integer missing;
    integer newHp;
    if (player == "") player = "Someone";
    gName = npcName;
    amount = rollDie(gHealDie) + gHealBonus;
    if (amount < 1) amount = 1;
    missing = npcMax - npcHp;
    if (amount > missing) amount = missing;
    if (amount < 0) amount = 0;
    newHp = npcHp + amount;
    sayAs(player, player + " heals " + npcName + " for " + (string)amount + ". (" + (string)newHp + "/" + (string)npcMax + " HP)");
    llMessageLinked(LINK_SET, LINK_BODY, "Z|HEAL|" + (string)av + "|" + (string)newHp, NULL_KEY);
}

counterJob(key av, string player, integer playerDef, integer playerHp, integer playerMax, integer defending, integer npcAtk, string npcName) {
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
    if (player == "") player = "Someone";
    gName = npcName;
    defStat = playerDef;
    if (defending) defStat = defStat + gDefendBonus;
    roll = resolve(npcAtk, defStat);
    margin = llList2Integer(roll, 0);
    damage = llList2Integer(roll, 1);
    crit = llList2Integer(roll, 2);
    atkDie = llList2Integer(roll, 3);
    atkTotal = llList2Integer(roll, 4);
    defDie = llList2Integer(roll, 5);
    defTotal = llList2Integer(roll, 6);
    if (damage > playerHp) damage = playerHp;
    newHp = playerHp - damage;
    sayAs(npcName, npcName + " attacks " + player + ".");
    if (defending) {
        bonus = (string)gDefendBonus;
        if (gDefendBonus >= 0) bonus = "+" + bonus;
        sayAs(player, player + " is defending (" + bonus + " Defense).");
    }
    sayRolls(npcName, npcAtk, atkDie, atkTotal, player, defStat, defDie, defTotal);
    narrateResult(npcName, player, margin, damage, crit, newHp, playerMax);
    llMessageLinked(LINK_SET, LINK_BODY, "Z|COUNTER|" + (string)av + "|" + (string)newHp + "|" + (string)damage, NULL_KEY);
}

onJob(string body) {
    list fields;
    string kind;
    key av;
    string player;
    fields = llParseStringKeepNulls(body, ["|"], []);
    kind = llList2String(fields, 1);
    av = (key)llList2String(fields, 2);
    player = llList2String(fields, 3);
    if (kind == "ATTACK") {
        attackJob(av, player, (integer)llList2String(fields, 4), (integer)llList2String(fields, 5), (integer)llList2String(fields, 6), (integer)llList2String(fields, 7), (integer)llList2String(fields, 9), llList2String(fields, 10));
    }
    else if (kind == "HEAL") {
        healJob(av, player, (integer)llList2String(fields, 4), (integer)llList2String(fields, 5), llList2String(fields, 6));
    }
    else if (kind == "COUNTER") {
        counterJob(av, player, (integer)llList2String(fields, 4), (integer)llList2String(fields, 5), (integer)llList2String(fields, 6), (integer)llList2String(fields, 7), (integer)llList2String(fields, 8), llList2String(fields, 9));
    }
}

onBody(string body) {
    string op;
    string rest;
    integer cut;
    string keyName;
    op = opOf(body);
    if (op == "RST") {
        llResetScript();
        return;
    }
    if (op == "J") {
        onJob(body);
        return;
    }
    if (op != "D") return;
    cut = llSubStringIndex(body, "\n");
    if (cut < 0) return;
    rest = llGetSubString(body, cut + 1, -1);
    cut = llSubStringIndex(rest, "\n");
    if (cut < 0) return;
    keyName = llGetSubString(rest, 0, cut - 1);
    applyDie(keyName, (integer)llGetSubString(rest, cut + 1, -1));
}

default {
    state_entry() {
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
        gName = llGetObjectName();
    }

    on_rez(integer start) {
        llResetScript();
    }

    changed(integer change) {
        if (change & CHANGED_OWNER) llResetScript();
        if (change & CHANGED_INVENTORY) llResetScript();
    }

    link_message(integer sender, integer num, string str, key id) {
        if (num == LINK_BODY) onBody(str);
    }
}
