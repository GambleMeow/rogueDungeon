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

function terrainCoefficients(terrainId) {
  if (terrainId === "arena_open") return { heroDmgMul: 1.1, bossDmgMul: 0.94 };
  if (terrainId === "arena_outer_ring") return { heroDmgMul: 1.07, bossDmgMul: 0.91 };
  if (terrainId === "arena_edge_risky") return { heroDmgMul: 0.9, bossDmgMul: 1.14 };
  if (terrainId === "arena_line_skill") return { heroDmgMul: 0.93, bossDmgMul: 1.12 };
  if (terrainId === "arena_fan_facing") return { heroDmgMul: 0.95, bossDmgMul: 1.1 };
  if (terrainId === "arena_circle_warning") return { heroDmgMul: 0.92, bossDmgMul: 1.13 };
  if (terrainId === "arena_random_reposition") return { heroDmgMul: 0.88, bossDmgMul: 1.16 };
  if (terrainId === "arena_stack_spread_switch") return { heroDmgMul: 0.97, bossDmgMul: 1.05 };
  return { heroDmgMul: 1.0, bossDmgMul: 1.0 };
}

function roleBaseDamage(role) {
  if (role === "burst") return 230;
  if (role === "dps_sustain") return 168;
  if (role === "dps_cycle") return 158;
  if (role === "board_control") return 132;
  if (role === "control") return 124;
  if (role === "survival") return 98;
  return 142;
}

function applyTerrainActionRule(action, terrainTags, rule) {
  const id = String(action?.actionId || "");
  const deny = rule?.actionDenyList || [];
  const requireTag = rule?.actionRequireTag || {};
  if (deny.includes(id)) return { denied: true, scoreDelta: -999 };
  if (requireTag[id] && !terrainTags.includes(requireTag[id])) return { denied: true, scoreDelta: -999 };
  const delta = Number((rule?.actionPriorityDelta || {})[id] || 0);
  return { denied: false, scoreDelta: delta };
}

function pickAction(hero, terrainTags, terrainRule) {
  const actions = hero.actionBindings || [];
  if (actions.length === 0) return null;
  let best = null;
  let bestScore = -1e9;
  for (const a of actions) {
    const role = String(a.role || "");
    let score = Number(a.priority || 0);
    const rr = applyTerrainActionRule(a, terrainTags, terrainRule);
    if (rr.denied) continue;
    score += rr.scoreDelta;
    if (terrainTags.includes("movement_check") && role === "mobility") score += 12;
    if (terrainTags.includes("circle_aoe_zone") && role === "survival") score += 10;
    if (terrainTags.includes("fan_aoe_facing") && role === "control") score += 8;
    if (score > bestScore) {
      bestScore = score;
      best = a;
    }
  }
  return best || actions[0];
}

function estimateRisk(pos, instance, tags) {
  let r = 1.0;
  if ((instance.warningZones || []).length > 0) r *= 1.09;
  if ((instance.blockers || []).length > 1 && tags.includes("anti_stuck_layout")) r *= 1.06;
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
    const s = skills.find((x) => {
      const id = String(x.skillId || "");
      return id.includes("ring") || id.includes("nova") || id.includes("burst");
    });
    if (s) return s;
  }
  return skills[0];
}

function bossSkillDamage(skillId, tags, coef) {
  let d = 108;
  const id = String(skillId || "");
  if (id.includes("charge") || id.includes("burst")) d = 150;
  else if (id.includes("ring") || id.includes("nova")) d = 130;
  if (tags.includes("line_skill_lane")) d = Math.floor(d * 1.08);
  if (tags.includes("fan_aoe_facing")) d = Math.floor(d * 1.06);
  if (tags.includes("circle_aoe_zone")) d = Math.floor(d * 1.1);
  if (tags.includes("open_arena")) d = Math.floor(d * 0.95);
  d = Math.floor(d * coef.bossDmgMul);
  return d;
}

function simulateWave(runtime, waveObj, heroes) {
  const boss = (runtime.boss.bosses || []).find((b) => b.id === waveObj.bossId) || {};
  const bossBehavior = (runtime.boss.bossBehavior21 || []).find((x) => x.bossId === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const tags = terrain.template.tags || [];
  const coef = terrainCoefficients(terrain.template.terrainId);
  const spawns = terrain.instance.heroSpawnPoints || [];

  let bossHp = Math.max(1, Number(boss.baseHp || 5000));
  let teamHp = heroes.map(() => 2200);
  const turns = [];

  for (let turn = 1; turn <= 12; turn++) {
    let heroDmg = 0;
    const heroCasts = [];
    for (let i = 0; i < heroes.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(heroes[i], tags, terrain.rule);
      const role = String(action?.role || "dps_cycle");
      let dmg = roleBaseDamage(role);
      const risk = estimateRisk(spawns[i] || { x: 25, y: 50 }, terrain.instance, tags);
      const offense = 1 / Math.max(0.84, Math.min(1.25, risk));
      dmg = Math.floor(dmg * offense * coef.heroDmgMul);
      heroDmg += dmg;
      heroCasts.push({
        heroId: heroes[i].heroId,
        heroName: heroes[i].heroName,
        actionId: action?.actionId || "none",
        role,
        estRisk: Number(risk.toFixed(2)),
        damage: dmg
      });
    }

    bossHp = Math.max(0, bossHp - heroDmg);
    const bossSkill = chooseBossSkill(bossBehavior, tags);
    const bossDmg = bossSkillDamage(bossSkill.skillId, tags, coef);

    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      const risk = estimateRisk(spawns[i] || { x: 25, y: 50 }, terrain.instance, tags);
      teamHp[i] = Math.max(0, teamHp[i] - Math.floor(bossDmg * risk));
    }

    turns.push({
      turn,
      heroTurnDamage: heroDmg,
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
    terrain: {
      terrainId: terrain.template.terrainId || "unknown",
      name: terrain.template.name || "unknown",
      tags,
      warningZoneCount: (terrain.instance.warningZones || []).length,
      blockerCount: (terrain.instance.blockers || []).length,
      safeZoneCount: (terrain.instance.safeZones || []).length,
      deniedActions: terrain.rule.actionDenyList || []
    },
    result: bossHp <= 0 && alive > 0 ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: alive,
    turns
  };
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = (runtime.hero.heroes || []).slice(0, 4);
  const waves = runtime.boss.waves || [];

  const replay = {
    meta: {
      version: "1.0-sim-v4",
      generatedAt: "2026-03-10",
      mapId: 180750,
      terrainRuleAware: true,
      heroTeam: heroes.map((h) => ({ heroId: h.heroId, heroName: h.heroName }))
    },
    waveReplays: []
  };

  let wins = 0;
  for (const w of waves) {
    const r = simulateWave(runtime, w, heroes);
    replay.waveReplays.push(r);
    if (r.result === "win") wins += 1;
  }
  replay.summary = {
    totalWaves: waves.length,
    wins,
    losses: waves.length - wins,
    clearAll: wins === waves.length
  };

  fs.writeFileSync("battle_replay_v4.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v4.json generated");
  console.log("SIM_V4_SUMMARY", replay.summary);
}

main();
