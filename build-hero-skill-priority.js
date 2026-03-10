const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function collectTexts(hero) {
  const accessories = hero.accessories || [];
  const talents = hero.talents || [];
  const textA = accessories.map((a) => `${a.name || ""} ${a.description || ""}`.trim());
  const textT = talents.map((t) => t.description || "");
  return textA.concat(textT).filter(Boolean);
}

function hasAny(text, words) {
  for (const w of words) {
    if (text.includes(w)) return true;
  }
  return false;
}

function firstEvidence(texts, words) {
  for (const t of texts) {
    if (hasAny(t, words)) return t;
  }
  return "unknown";
}

function inferActionPack(hero) {
  const texts = collectTexts(hero);
  const all = texts.join(" | ");

  const kw = {
    summon: ["召唤", "守卫", "图腾", "随从", "分身", "傀儡", "水元素"],
    move: ["位移", "冲锋", "跳", "闪烁", "传送", "突进"],
    aoe: ["范围", "扇形", "全体", "周围", "圆形", "多段", "连环"],
    control: ["眩晕", "击飞", "减速", "沉默", "冰冻", "拉扯", "缠绕"],
    defense: ["护盾", "护甲", "减伤", "无敌", "回复", "治疗", "吸血", "格挡"],
    execute: ["斩杀", "额外伤害", "暴击伤害", "易伤", "增伤", "真实伤害"],
    economy: ["金币", "结算", "市场", "刷新", "负债", "偿还"],
    attack: ["普攻", "攻击后", "攻击时", "攻速", "连击", "攻击特效"]
  };

  const flags = {
    summon: hasAny(all, kw.summon),
    move: hasAny(all, kw.move),
    aoe: hasAny(all, kw.aoe),
    control: hasAny(all, kw.control),
    defense: hasAny(all, kw.defense),
    execute: hasAny(all, kw.execute),
    economy: hasAny(all, kw.economy),
    attack: hasAny(all, kw.attack)
  };

  const actions = [];

  // Core attack/action
  actions.push({
    actionId: "primary_pattern",
    priority: 100,
    castCondition: flags.attack ? "on_attack_window" : "on_skill_window",
    targetRule: flags.aoe ? "max_units_in_range" : "current_aggro_target",
    cooldownHintSec: "baseline_loop",
    role: flags.attack ? "dps_sustain" : "dps_cycle",
    evidence: firstEvidence(texts, flags.attack ? kw.attack : ["技能", "法术", "释放"])
  });

  if (flags.summon) {
    actions.push({
      actionId: "summon_maintenance",
      priority: 95,
      castCondition: "if_summon_count_below_threshold",
      targetRule: "safe_spawn_zone_near_self",
      cooldownHintSec: "unknown",
      role: "board_control",
      evidence: firstEvidence(texts, kw.summon)
    });
  }

  if (flags.control) {
    actions.push({
      actionId: "control_cast",
      priority: 90,
      castCondition: "if_enemy_cluster_or_elite_casting",
      targetRule: "highest_threat_or_cluster_center",
      cooldownHintSec: "unknown",
      role: "control",
      evidence: firstEvidence(texts, kw.control)
    });
  }

  if (flags.defense) {
    actions.push({
      actionId: "defensive_window",
      priority: 92,
      castCondition: "if_hp_below_55_or_focused",
      targetRule: "self_or_lowest_hp_ally",
      cooldownHintSec: "unknown",
      role: "survival",
      evidence: firstEvidence(texts, kw.defense)
    });
  }

  if (flags.execute) {
    actions.push({
      actionId: "burst_or_execute",
      priority: 93,
      castCondition: "if_target_vulnerable_or_buffed",
      targetRule: "lowest_effective_hp_elite",
      cooldownHintSec: "unknown",
      role: "burst",
      evidence: firstEvidence(texts, kw.execute)
    });
  }

  if (flags.move) {
    actions.push({
      actionId: "mobility_reposition",
      priority: 88,
      castCondition: "if_out_of_position_or_need_gap_close",
      targetRule: "flank_or_backline_entry",
      cooldownHintSec: "unknown",
      role: "mobility",
      evidence: firstEvidence(texts, kw.move)
    });
  }

  if (flags.economy) {
    actions.push({
      actionId: "economy_convert",
      priority: 70,
      castCondition: "non_combat_or_round_end_phase",
      targetRule: "self",
      cooldownHintSec: "round_based",
      role: "economy",
      evidence: firstEvidence(texts, kw.economy)
    });
  }

  actions.sort((a, b) => b.priority - a.priority);

  const opener = actions[0]?.actionId || "primary_pattern";
  const fallback = flags.attack ? "kite_and_auto_attack" : "safe_range_skill_cycle";

  return {
    flags,
    opener,
    fallback,
    actions
  };
}

function main() {
  const raw = readJson("hero_static_data.json");
  const behavior = readJson("hero_behavior_v1.json");
  const behaviorMap = {};
  for (const h of behavior.heroes || []) behaviorMap[h.heroId] = h;

  const heroes = raw.data || [];

  const outputHeroes = heroes.map((h) => {
    const pack = inferActionPack(h);
    const base = behaviorMap[h.id] || {};
    return {
      heroId: h.id,
      heroName: h.name,
      combatArchetype: base.combatArchetype || "hybrid",
      damageProfile: base.damageProfile || "mixed",
      triggerStyle: base.triggerStyle || ["mixed"],
      skillPriorityModel: {
        openerAction: pack.opener,
        fallbackLoop: pack.fallback,
        actionCount: pack.actions.length,
        actions: pack.actions
      },
      behaviorFlags: pack.flags,
      confidence: Number((0.7 + Math.min(0.25, pack.actions.length * 0.03)).toFixed(2))
    };
  });

  const output = {
    meta: {
      version: "2.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sources: ["hero_static_data.json", "hero_behavior_v1.json"],
      note: "Per-hero action priority model for direct Godot behavior tree mapping."
    },
    summary: {
      heroCount: outputHeroes.length,
      avgActionsPerHero: Number(
        (outputHeroes.reduce((s, x) => s + x.skillPriorityModel.actionCount, 0) / (outputHeroes.length || 1)).toFixed(2)
      )
    },
    heroes: outputHeroes
  };

  fs.writeFileSync("hero_skill_priority_v2.json", JSON.stringify(output, null, 2), "utf8");
  console.log("hero_skill_priority_v2.json generated");
}

main();
