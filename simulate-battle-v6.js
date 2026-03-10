const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function terrainForWave(runtime, wave) {
  const tw = runtime.terrain?.waves || [];
  const templates = runtime.terrain?.templates || [];
  const instances = runtime.terrain?.instances || [];
  const rules = runtime.terrain?.actionRules || [];
  const tMap = {};
  const iMap = {};
  const rMap = {};
  for (const t of templates) tMap[t.terrainId] = t;
  for (const i of instances) iMap[i.terrainId] = i;
  for (const r of rules) rMap[r.terrainId] = r;
  const row = tw.find((x) => Number(x.wave) === Number(wave));
  const pool = row?.terrainPool || [];
  const terrainId = pool.length > 0 ? pool[wave % pool.length] : "arena_open";
  return {
    template: tMap[terrainId] || { terrainId, name: terrainId, tags: [] },
    instance: iMap[terrainId] || { terrainId, heroSpawnPoints: [], warningZones: [], blockers: [], safeZones: [] },
    rule: rMap[terrainId] || { actionPriorityDelta: {}, actionDenyList: [], actionRequireTag: {} }
  };
}

function terrainCoef(terrainId) {
  const map = {
    arena_open: { heroDmgMul: 1.12, bossDmgMul: 0.93 },
    arena_outer_ring: { heroDmgMul: 1.09, bossDmgMul: 0.9 },
    arena_edge_risky: { heroDmgMul: 0.89, bossDmgMul: 1.14 },
    arena_line_skill: { heroDmgMul: 0.92, bossDmgMul: 1.12 },
    arena_fan_facing: { heroDmgMul: 0.95, bossDmgMul: 1.1 },
    arena_circle_warning: { heroDmgMul: 0.92, bossDmgMul: 1.13 },
    arena_random_reposition: { heroDmgMul: 0.87, bossDmgMul: 1.16 },
    arena_stack_spread_switch: { heroDmgMul: 0.98, bossDmgMul: 1.04 }
  };
  return map[terrainId] || { heroDmgMul: 1.0, bossDmgMul: 1.0 };
}

function roleBaseDamage(role) {
  const map = {
    burst: 235,
    dps_sustain: 170,
    dps_cycle: 160,
    board_control: 136,
    control: 128,
    survival: 102
  };
  return map[role] || 145;
}

function bossSkillTags(bossBehavior) {
  const text = (bossBehavior?.skills || []).map((s) => String(s.skillId || "")).join("|");
  const tags = [];
  if (text.includes("charge")) tags.push("charge_pressure");
  if (text.includes("ring") || text.includes("nova")) tags.push("zone_pressure");
  if (text.includes("reposition")) tags.push("reposition_pressure");
  if (text.includes("summon")) tags.push("summon_pressure");
  return tags;
}

function scoreHeroForWave(hero, terrainTags, bossTags) {
  const f = hero.behaviorFlags || {};
  let s = 0;
  if (terrainTags.includes("movement_check") && f.move) s += 10;
  if (terrainTags.includes("line_skill_lane") && f.move) s += 8;
  if (terrainTags.includes("fan_aoe_facing") && f.control) s += 7;
  if (terrainTags.includes("circle_aoe_zone") && f.defense) s += 8;
  if (terrainTags.includes("spread_requirement") && f.summon) s -= 8;
  if (terrainTags.includes("stack_requirement") && f.summon) s += 4;
  if (terrainTags.includes("anti_stuck_layout") && f.move) s += 8;
  if (bossTags.includes("charge_pressure") && f.defense) s += 8;
  if (bossTags.includes("zone_pressure") && f.defense) s += 8;
  if (bossTags.includes("reposition_pressure") && f.move) s += 7;
  if (bossTags.includes("summon_pressure") && f.control) s += 6;
  s += Math.min(6, Number(hero.guideCount || 0));
  return s;
}

function chooseTeam(allHeroes, terrainTags, bossTags) {
  const scored = allHeroes
    .map((h) => ({ hero: h, score: scoreHeroForWave(h, terrainTags, bossTags) }))
    .sort((a, b) => b.score - a.score);
  const out = [];
  const arch = {};
  for (const it of scored) {
    if (out.length >= 4) break;
    const a = String(it.hero.combatArchetype || "hybrid");
    if ((arch[a] || 0) >= 2) continue;
    out.push(it.hero);
    arch[a] = (arch[a] || 0) + 1;
  }
  for (const it of scored) {
    if (out.length >= 4) break;
    if (!out.includes(it.hero)) out.push(it.hero);
  }
  return out.slice(0, 4);
}

function teamSynergy(team, bossTags) {
  const archetypes = new Set(team.map((h) => h.combatArchetype || "hybrid"));
  const uniqueCount = archetypes.size;
  let dmgMul = 1 + Math.max(0, uniqueCount - 1) * 0.04;
  let dmgTakenMul = 1.0;

  let defenseCount = 0;
  let moveCount = 0;
  let controlCount = 0;
  for (const h of team) {
    const f = h.behaviorFlags || {};
    if (f.defense) defenseCount += 1;
    if (f.move) moveCount += 1;
    if (f.control) controlCount += 1;
  }

  if (bossTags.includes("charge_pressure") && defenseCount >= 2) dmgTakenMul *= 0.92;
  if (bossTags.includes("zone_pressure") && defenseCount >= 2) dmgTakenMul *= 0.9;
  if (bossTags.includes("reposition_pressure") && moveCount >= 2) dmgTakenMul *= 0.93;
  if (bossTags.includes("summon_pressure") && controlCount >= 2) dmgMul *= 1.05;

  return { dmgMul, dmgTakenMul };
}

function actionRuleAdjust(action, terrainTags, rule) {
  const id = String(action?.actionId || "");
  if ((rule.actionDenyList || []).includes(id)) return { denied: true, delta: -999 };
  const req = (rule.actionRequireTag || {})[id];
  if (req && !terrainTags.includes(req)) return { denied: true, delta: -999 };
  return { denied: false, delta: Number((rule.actionPriorityDelta || {})[id] || 0) };
}

function pickAction(hero, terrainTags, terrainRule) {
  const arr = hero.actionBindings || [];
  if (arr.length === 0) return null;
  let best = arr[0];
  let bestScore = -1e9;
  for (const a of arr) {
    let score = Number(a.priority || 0);
    const rr = actionRuleAdjust(a, terrainTags, terrainRule);
    if (rr.denied) continue;
    score += rr.delta;
    if (terrainTags.includes("movement_check") && a.role === "mobility") score += 10;
    if (terrainTags.includes("circle_aoe_zone") && a.role === "survival") score += 10;
    if (score > bestScore) {
      best = a;
      bestScore = score;
    }
  }
  return best;
}

function riskAtPos(pos, instance, tags) {
  let r = 1.0;
  if ((instance.warningZones || []).length > 0) r *= 1.09;
  if (tags.includes("line_skill_lane") && Math.abs((pos.y || 50) - 50) < 8) r *= 1.12;
  if (tags.includes("edge_hugging") && (pos.x || 50) > 80) r *= 1.13;
  if ((instance.safeZones || []).length > 0 && (pos.x || 50) < 56) r *= 0.91;
  return r;
}

function chooseBossSkill(bossBehavior, tags) {
  const skills = bossBehavior?.skills || [];
  if (skills.length === 0) return { skillId: "unknown" };
  if (tags.includes("anti_stuck_layout")) {
    const s = skills.find((x) => String(x.skillId || "").includes("reposition"));
    if (s) return s;
  }
  if (tags.includes("circle_aoe_zone")) {
    const s = skills.find((x) => /ring|nova|burst/.test(String(x.skillId || "")));
    if (s) return s;
  }
  return skills[0];
}

function bossSkillDamage(skillId, tags, coef) {
  let d = 108;
  const id = String(skillId || "");
  if (id.includes("charge") || id.includes("burst")) d = 152;
  else if (id.includes("ring") || id.includes("nova")) d = 132;
  if (tags.includes("line_skill_lane")) d = Math.floor(d * 1.08);
  if (tags.includes("circle_aoe_zone")) d = Math.floor(d * 1.1);
  if (tags.includes("open_arena")) d = Math.floor(d * 0.95);
  return Math.floor(d * coef.bossDmgMul);
}

function simulateWave(runtime, waveObj, allHeroes) {
  const boss = (runtime.boss.bosses || []).find((b) => b.id === waveObj.bossId) || {};
  const bossBehavior = (runtime.boss.bossBehavior21 || []).find((x) => x.bossId === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const tags = terrain.template.tags || [];
  const bTags = bossSkillTags(bossBehavior);
  const team = chooseTeam(allHeroes, tags, bTags);
  const syn = teamSynergy(team, bTags);
  const coef = terrainCoef(terrain.template.terrainId);
  const spawns = terrain.instance.heroSpawnPoints || [];

  let bossHp = Math.max(1, Number(boss.baseHp || 5000));
  let teamHp = team.map(() => 2200);
  const turns = [];

  for (let turn = 1; turn <= 14; turn++) {
    let heroTurnDamage = 0;
    const heroCasts = [];
    for (let i = 0; i < team.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(team[i], tags, terrain.rule);
      const role = String(action?.role || "dps_cycle");
      const risk = riskAtPos(spawns[i] || { x: 25, y: 50 }, terrain.instance, tags);
      const offenseMul = 1 / Math.max(0.84, Math.min(1.25, risk));
      const dmg = Math.floor(roleBaseDamage(role) * offenseMul * coef.heroDmgMul * syn.dmgMul);
      heroTurnDamage += dmg;
      heroCasts.push({ heroId: team[i].heroId, heroName: team[i].heroName, actionId: action?.actionId || "none", role, damage: dmg });
    }

    bossHp = Math.max(0, bossHp - heroTurnDamage);
    const bossSkill = chooseBossSkill(bossBehavior, tags);
    const bossDmg = bossSkillDamage(bossSkill.skillId, tags, coef);
    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      const risk = riskAtPos(spawns[i] || { x: 25, y: 50 }, terrain.instance, tags);
      teamHp[i] = Math.max(0, teamHp[i] - Math.floor(bossDmg * risk * syn.dmgTakenMul));
    }

    turns.push({
      turn,
      heroTurnDamage,
      bossSkillId: bossSkill.skillId || "unknown",
      bossDamageBase: bossDmg,
      bossHpAfterTurn: bossHp,
      teamHpAfterTurn: [...teamHp],
      heroCasts
    });

    const alive = teamHp.filter((x) => x > 0).length;
    if (bossHp <= 0 || alive === 0) break;
  }

  const alive = teamHp.filter((x) => x > 0).length;
  return {
    wave: waveObj.wave,
    bossId: waveObj.bossId,
    bossName: boss.name || waveObj.bossId,
    selectedTeam: team.map((h) => ({ heroId: h.heroId, heroName: h.heroName, archetype: h.combatArchetype })),
    terrain: { terrainId: terrain.template.terrainId || "unknown", name: terrain.template.name || "unknown", tags },
    synergy: syn,
    result: bossHp <= 0 && alive > 0 ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: alive,
    turns
  };
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = runtime.hero.heroes || [];
  const waves = runtime.boss.waves || [];

  const replay = { meta: { version: "1.0-sim-v6", generatedAt: "2026-03-10", mapId: 180750, dynamicTeamSelection: true, synergyEnabled: true }, waveReplays: [] };
  let wins = 0;
  for (const w of waves) {
    const r = simulateWave(runtime, w, heroes);
    replay.waveReplays.push(r);
    if (r.result === "win") wins += 1;
  }
  replay.summary = { totalWaves: waves.length, wins, losses: waves.length - wins, clearAll: wins === waves.length };
  fs.writeFileSync("battle_replay_v6.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v6.json generated");
  console.log("SIM_V6_SUMMARY", replay.summary);
}

main();
