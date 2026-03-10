const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function collectTexts(hero) {
  const acc = (hero.accessories || []).map((x) => x.description || "");
  const tal = (hero.talents || []).map((x) => x.description || "");
  return acc.concat(tal).filter(Boolean);
}

function countHits(text, words) {
  let n = 0;
  for (const w of words) {
    if (text.includes(w)) n += 1;
  }
  return n;
}

function pickTopEvidence(texts, keywords, maxCount) {
  const out = [];
  for (const t of texts) {
    let matched = false;
    for (const k of keywords) {
      if (t.includes(k)) {
        matched = true;
        break;
      }
    }
    if (matched) {
      out.push(t);
      if (out.length >= maxCount) break;
    }
  }
  return out;
}

function classifyHero(hero) {
  const texts = collectTexts(hero);
  const all = texts.join(" | ");

  const summonerWords = ["召唤", "召喚", "召唤物", "随从", "守卫", "图腾"];
  const casterWords = ["技能", "法术", "魔法", "施法", "法伤", "法术伤害", "法强"];
  const attackWords = ["普攻", "攻击", "攻速", "暴击", "攻击特效", "连击"];
  const tankWords = ["护甲", "减伤", "生命", "格挡", "反伤", "承伤", "无敌"];
  const controlWords = ["眩晕", "击飞", "减速", "沉默", "缠绕", "冰冻", "拉扯"];
  const economyWords = ["金币", "经济", "刷新", "市场", "结算", "负债", "偿还"];

  const score = {
    summoner: countHits(all, summonerWords),
    caster: countHits(all, casterWords),
    attacker: countHits(all, attackWords),
    tank: countHits(all, tankWords),
    control: countHits(all, controlWords),
    economy: countHits(all, economyWords)
  };

  let combatArchetype = "hybrid";
  if (score.summoner >= 2 && score.summoner >= score.attacker - 1) {
    combatArchetype = "summoner";
  } else if (score.tank >= 4 && score.control >= 2) {
    combatArchetype = "tank_control";
  } else if (score.caster >= 4 && score.caster >= score.attacker) {
    combatArchetype = "caster";
  } else if (score.attacker >= 4 && score.attacker >= score.caster) {
    combatArchetype = "auto_attack";
  }

  let damageProfile = "mixed";
  const spellHits = countHits(all, ["法术伤害", "法伤", "法术", "魔法"]);
  const physicalHits = countHits(all, ["物理伤害", "普攻", "暴击", "攻击特效"]);
  if (spellHits >= physicalHits + 2) damageProfile = "spell";
  else if (physicalHits >= spellHits + 2) damageProfile = "physical";

  const scalingAxes = [];
  if (all.includes("力量")) scalingAxes.push("strength");
  if (all.includes("敏捷")) scalingAxes.push("agility");
  if (all.includes("智力")) scalingAxes.push("intellect");
  if (all.includes("生命")) scalingAxes.push("hp");
  if (all.includes("魔法")) scalingAxes.push("mana");
  if (all.includes("攻速")) scalingAxes.push("attack_speed");
  if (all.includes("暴击")) scalingAxes.push("crit");
  if (all.includes("召唤")) scalingAxes.push("summon_power");

  const triggerWords = {
    onAttack: ["攻击时", "普攻", "攻击后", "命中后"],
    onCast: ["使用技能后", "施法后", "技能后"],
    onKill: ["击杀", "死亡", "敌人死亡"],
    onRoundEnd: ["结算", "战斗结束后"],
    onShop: ["刷新市场", "市场", "商店"]
  };
  const triggerStyle = [];
  if (countHits(all, triggerWords.onAttack) > 0) triggerStyle.push("on_attack");
  if (countHits(all, triggerWords.onCast) > 0) triggerStyle.push("on_cast");
  if (countHits(all, triggerWords.onKill) > 0) triggerStyle.push("on_kill");
  if (countHits(all, triggerWords.onRoundEnd) > 0) triggerStyle.push("on_round_end");
  if (countHits(all, triggerWords.onShop) > 0) triggerStyle.push("on_shop");
  if (triggerStyle.length === 0) triggerStyle.push("mixed");

  const evidence = pickTopEvidence(
    texts,
    [
      "召唤", "法术", "普攻", "暴击", "攻速", "护甲", "生命",
      "减速", "眩晕", "结算", "市场", "负债", "刷新"
    ],
    5
  );

  const accessoryTypes = {};
  for (const a of hero.accessories || []) {
    const t = a.type || "UNKNOWN";
    accessoryTypes[t] = (accessoryTypes[t] || 0) + 1;
  }

  const confidenceScore = Math.min(
    0.95,
    0.45 +
      Math.min(0.35, texts.length * 0.01) +
      Math.min(0.15, evidence.length * 0.03)
  );

  return {
    heroId: hero.id,
    heroName: hero.name,
    guideCount: hero.guideCount || 0,
    combatArchetype,
    damageProfile,
    scalingAxes: [...new Set(scalingAxes)],
    triggerStyle,
    accessoryTypeDistribution: accessoryTypes,
    behaviorTreeHints: {
      opener: combatArchetype === "summoner" ? "summon_first_then_kite" : "apply_core_buff_then_trade",
      loop: triggerStyle.includes("on_attack") ? "maintain_attack_uptime" : "skill_cycle_priority",
      survival: score.tank >= 2 ? "frontline_with_defensive_windows" : "reposition_on_focus_fire"
    },
    controlLevel: score.control >= 4 ? "high" : score.control >= 2 ? "medium" : "low",
    economyCoupling: score.economy >= 2 ? "high" : score.economy === 1 ? "medium" : "low",
    confidence: Number(confidenceScore.toFixed(2)),
    evidence
  };
}

function main() {
  const raw = readJson("hero_static_data.json");
  const heroes = raw.data || [];
  const heroBehaviors = heroes.map(classifyHero);

  const archetypeCount = {};
  for (const h of heroBehaviors) {
    archetypeCount[h.combatArchetype] = (archetypeCount[h.combatArchetype] || 0) + 1;
  }

  const output = {
    meta: {
      version: "1.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sourceFile: "hero_static_data.json",
      note: "Heuristic hero behavior model for Godot runtime setup."
    },
    summary: {
      heroCount: heroBehaviors.length,
      archetypeCount
    },
    heroes: heroBehaviors
  };

  fs.writeFileSync("hero_behavior_v1.json", JSON.stringify(output, null, 2), "utf8");
  console.log("hero_behavior_v1.json generated");
}

main();
