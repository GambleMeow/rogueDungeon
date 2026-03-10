const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function uniq(arr) {
  return [...new Set(arr)];
}

function defaultTimingByRole(role) {
  if (role === "burst") return { windupSec: 0.35, backswingSec: 0.25 };
  if (role === "control") return { windupSec: 0.28, backswingSec: 0.2 };
  if (role === "survival") return { windupSec: 0.18, backswingSec: 0.15 };
  if (role === "mobility") return { windupSec: 0.12, backswingSec: 0.1 };
  if (role === "board_control") return { windupSec: 0.25, backswingSec: 0.18 };
  if (role === "economy") return { windupSec: 0.05, backswingSec: 0.05 };
  return { windupSec: 0.22, backswingSec: 0.16 };
}

function defaultSlotByAction(actionId) {
  if (actionId === "primary_pattern") return "PRIMARY";
  if (actionId === "defensive_window") return "DEFENSE";
  if (actionId === "control_cast") return "CONTROL";
  if (actionId === "burst_or_execute") return "BURST";
  if (actionId === "mobility_reposition") return "MOBILITY";
  if (actionId === "summon_maintenance") return "SUMMON";
  if (actionId === "economy_convert") return "UTILITY";
  return "UTILITY";
}

function defaultAnimTag(actionId, role) {
  if (actionId === "primary_pattern") return "cast_primary";
  if (actionId === "defensive_window") return "cast_defense";
  if (actionId === "control_cast") return "cast_control";
  if (actionId === "burst_or_execute") return "cast_burst";
  if (actionId === "mobility_reposition") return "cast_mobility";
  if (actionId === "summon_maintenance") return "cast_summon";
  if (actionId === "economy_convert") return "cast_utility";
  return `cast_${(role || "utility").toLowerCase()}`;
}

function makeActionCatalog(heroes) {
  const allActions = [];
  for (const h of heroes) {
    for (const a of h.actions || []) allActions.push(a);
  }

  const ids = uniq(allActions.map((a) => a.actionId));
  const catalog = ids.map((id) => {
    const samples = allActions.filter((a) => a.actionId === id);
    const roles = uniq(samples.map((a) => a.role).filter(Boolean));
    const topRole = roles[0] || "utility";
    const slots = uniq(samples.map((a) => defaultSlotByAction(a.actionId)));
    const timing = defaultTimingByRole(topRole);

    return {
      actionId: id,
      role: topRole,
      defaultSkillSlot: slots[0],
      animationTag: defaultAnimTag(id, topRole),
      castTiming: timing,
      cancellableWindowSec: 0.08,
      allowedInPhases: uniq(samples.map((a) => a.condition?.phase || "combat")),
      targetSelectors: uniq(samples.map((a) => a.targeting?.selector).filter(Boolean))
    };
  });

  catalog.sort((a, b) => a.actionId.localeCompare(b.actionId));
  return catalog;
}

function enrichHeroActions(hero, catalogMap) {
  const bindings = [];
  for (const action of hero.actions || []) {
    const c = catalogMap[action.actionId];
    const castTiming = c ? c.castTiming : defaultTimingByRole(action.role);
    const binding = {
      actionId: action.actionId,
      priority: action.priority,
      skillSlot: c ? c.defaultSkillSlot : defaultSlotByAction(action.actionId),
      animationTag: c ? c.animationTag : defaultAnimTag(action.actionId, action.role),
      castTiming,
      cancelPolicy: {
        canBeInterrupted: action.role !== "burst",
        invulnDuringCast: action.role === "mobility" || action.role === "defensive_window"
      },
      condition: action.condition,
      targeting: action.targeting,
      cooldown: action.cooldown,
      evidence: action.evidence
    };
    bindings.push(binding);
  }
  return bindings;
}

function main() {
  const v3 = readJson("hero_skill_priority_v3.json");
  const heroes = v3.heroes || [];

  const actionCatalog = makeActionCatalog(heroes);
  const catalogMap = {};
  for (const a of actionCatalog) catalogMap[a.actionId] = a;

  const heroBindings = heroes.map((h) => ({
    heroId: h.heroId,
    heroName: h.heroName,
    combatArchetype: h.combatArchetype,
    damageProfile: h.damageProfile,
    behaviorFlags: h.behaviorFlags,
    treeConfig: h.treeConfig,
    actionBindings: enrichHeroActions(h, catalogMap)
  }));

  const slotStats = {};
  for (const h of heroBindings) {
    for (const a of h.actionBindings) {
      slotStats[a.skillSlot] = (slotStats[a.skillSlot] || 0) + 1;
    }
  }

  const out = {
    meta: {
      version: "4.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sources: ["hero_skill_priority_v3.json"],
      note: "Unified action dictionary + per-hero action bindings for Godot runtime."
    },
    summary: {
      heroCount: heroBindings.length,
      actionCatalogCount: actionCatalog.length,
      slotStats
    },
    actionCatalog,
    heroActionBindings: heroBindings
  };

  fs.writeFileSync("hero_skill_priority_v4.json", JSON.stringify(out, null, 2), "utf8");
  console.log("hero_skill_priority_v4.json generated");
}

main();
