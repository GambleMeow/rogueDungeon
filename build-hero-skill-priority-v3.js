const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function mapCondition(action) {
  const c = action.castCondition || "";
  const id = action.actionId || "";

  const condition = {
    hpBelow: null,
    enemyCountMin: null,
    targetDistance: null,
    requireBuff: null,
    requireDebuffOnTarget: null,
    requireSummonBelow: null,
    phase: "combat",
    event: null
  };

  if (c.includes("if_hp_below_55")) condition.hpBelow = 0.55;
  if (c.includes("if_enemy_cluster")) condition.enemyCountMin = 3;
  if (c.includes("if_summon_count_below_threshold")) condition.requireSummonBelow = 2;
  if (c.includes("if_target_vulnerable_or_buffed")) {
    condition.requireBuff = "self_damage_window";
    condition.requireDebuffOnTarget = "vulnerable_or_armor_break";
  }
  if (c.includes("if_out_of_position_or_need_gap_close")) condition.targetDistance = { min: 450, max: 1400 };
  if (c.includes("on_attack_window")) condition.event = "on_attack";
  if (c.includes("on_skill_window")) condition.event = "on_skill_cycle";
  if (c.includes("non_combat_or_round_end_phase")) {
    condition.phase = "round_end";
    condition.event = "on_round_end";
  }

  if (id === "mobility_reposition" && !condition.targetDistance) {
    condition.targetDistance = { min: 500, max: 1600 };
  }
  if (id === "control_cast" && !condition.enemyCountMin) {
    condition.enemyCountMin = 2;
  }
  if (id === "defensive_window" && condition.hpBelow === null) {
    condition.hpBelow = 0.6;
  }
  if (id === "economy_convert") {
    condition.phase = "round_end";
    condition.event = "on_round_end";
  }

  return condition;
}

function mapTargetRule(action) {
  const rule = action.targetRule || "";
  const model = {
    selector: "current_aggro",
    aoeCenter: null,
    allyPolicy: null
  };

  if (rule.includes("max_units_in_range")) {
    model.selector = "enemy_cluster_max";
    model.aoeCenter = "cluster_center";
  } else if (rule.includes("highest_threat_or_cluster_center")) {
    model.selector = "threat_or_cluster";
    model.aoeCenter = "adaptive";
  } else if (rule.includes("lowest_effective_hp_elite")) {
    model.selector = "elite_lowest_effective_hp";
  } else if (rule.includes("self_or_lowest_hp_ally")) {
    model.selector = "self_or_ally_lowest_hp";
    model.allyPolicy = "prefer_self_if_focused";
  } else if (rule.includes("safe_spawn_zone_near_self")) {
    model.selector = "spawn_zone_near_self";
  } else if (rule.includes("flank_or_backline_entry")) {
    model.selector = "backline_entry";
  } else if (rule.includes("self")) {
    model.selector = "self";
  }

  return model;
}

function mapCooldown(action) {
  const cd = action.cooldownHintSec;
  if (typeof cd === "number") return { type: "fixed", value: cd };
  if (cd === "baseline_loop") return { type: "gcd_loop", value: 1.0 };
  if (cd === "round_based") return { type: "round_end_only", value: null };
  return { type: "unknown", value: null };
}

function main() {
  const v2 = readJson("hero_skill_priority_v2.json");
  const heroes = v2.heroes || [];

  const v3Heroes = heroes.map((h) => {
    const actions = (h.skillPriorityModel?.actions || []).map((a) => ({
      actionId: a.actionId,
      priority: a.priority,
      role: a.role,
      condition: mapCondition(a),
      targeting: mapTargetRule(a),
      cooldown: mapCooldown(a),
      evidence: a.evidence || "unknown"
    }));

    return {
      heroId: h.heroId,
      heroName: h.heroName,
      combatArchetype: h.combatArchetype,
      damageProfile: h.damageProfile,
      behaviorFlags: h.behaviorFlags,
      treeConfig: {
        openerAction: h.skillPriorityModel?.openerAction || "primary_pattern",
        fallbackLoop: h.skillPriorityModel?.fallbackLoop || "safe_range_skill_cycle",
        selectorPolicy: "highest_priority_pass_condition",
        reevaluateIntervalSec: 0.2
      },
      actions
    };
  });

  const out = {
    meta: {
      version: "3.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sources: ["hero_skill_priority_v2.json"],
      note: "Condition-parameterized hero action model for Godot behavior trees."
    },
    summary: {
      heroCount: v3Heroes.length,
      avgActionCount: Number(
        (
          v3Heroes.reduce((sum, h) => sum + h.actions.length, 0) /
          (v3Heroes.length || 1)
        ).toFixed(2)
      )
    },
    heroes: v3Heroes
  };

  fs.writeFileSync("hero_skill_priority_v3.json", JSON.stringify(out, null, 2), "utf8");
  console.log("hero_skill_priority_v3.json generated");
}

main();
