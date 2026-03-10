const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function terrainForWave(runtime, wave) {
  const tw = runtime.terrain?.waves || [];
  const templates = runtime.terrain?.templates || [];
  const instances = runtime.terrain?.instances || [];
  const templateMap = {};
  const instanceMap = {};
  for (const t of templates) templateMap[t.terrainId] = t;
  for (const i of instances) instanceMap[i.terrainId] = i;

  const row = tw.find((x) => Number(x.wave) === Number(wave));
  const pool = row?.terrainPool || [];
  const terrainId = pool.length > 0 ? pool[wave % pool.length] : "arena_open";
  return {
    template: templateMap[terrainId] || { terrainId, name: terrainId, tags: [] },
    instance: instanceMap[terrainId] || { terrainId, heroSpawnPoints: [], warningZones: [], blockers: [], safeZones: [] }
  };
}

function roleBaseDamage(role) {
  if (role === "burst") return 220;
  if (role === "dps_sustain") return 165;
  if (role === "dps_cycle") return 155;
  if (role === "board_control") return 130;
  if (role === "control") return 120;
  if (role === "survival") return 95;
  return 140;
}

function pickAction(hero, tags) {
  const actions = hero.actionBindings || [];
  if (actions.length === 0) return null;
  let best = actions[0];
  let bestScore = -1e9;
  for (const a of actions) {
    let score = Number(a.priority || 0);
    const role = String(a.role || "");
    if (tags.includes("movement_check") && role === "mobility") score += 15;
    if (tags.includes("circle_aoe_zone") && role === "survival") score += 8;
    if (tags.includes("fan_aoe_facing") && role === "control") score += 8;
    if (tags.includes("stack_requirement") && role === "board_control") score += 6;
    if (tags.includes("anti_stuck_layout") && a.actionId === "mobility_reposition") score += 12;
    if (score > bestScore) {
      bestScore = score;
      best = a;
    }
  }
  return best;
}

function estimatePositionRisk(heroPos, terrainInstance, tags) {
  let risk = 1.0;
  const warnings = terrainInstance.warningZones || [];
  const blockers = terrainInstance.blockers || [];
  const safeZones = terrainInstance.safeZones || [];

  if (warnings.length > 0) risk *= 1.08;
  if (tags.includes("line_skill_lane") && Math.abs((heroPos.y || 50) - 50) < 6) risk *= 1.1;
  if (tags.includes("edge_hugging") && (heroPos.x || 50) > 80) risk *= 1.12;
  if (tags.includes("random_reposition_pressure")) risk *= 1.1;
  if (blockers.length > 1 && tags.includes("anti_stuck_layout")) risk *= 1.05;
  if (safeZones.length > 0 && (heroPos.x || 50) < 55) risk *= 0.92;

  return risk;
}

function bossSkillDamage(skillId, tags) {
  let dmg = 105;
  const id = String(skillId || "");
  if (id.includes("charge") || id.includes("burst")) dmg = 145;
  if (id.includes("ring") || id.includes("nova")) dmg = 125;

  if (tags.includes("line_skill_lane")) dmg = Math.floor(dmg * 1.08);
  if (tags.includes("fan_aoe_facing")) dmg = Math.floor(dmg * 1.06);
  if (tags.includes("circle_aoe_zone")) dmg = Math.floor(dmg * 1.1);
  if (tags.includes("open_arena")) dmg = Math.floor(dmg * 0.95);
  return dmg;
}

function chooseBossSkill(bossBehavior, tags) {
  const skills = bossBehavior?.skills || [];
  if (skills.length === 0) return { skillId: "unknown" };
  if (tags.includes("anti_stuck_layout")) {
    const s = skills.find((x) => String(x.skillId || "").includes("reposition"));
    if (s) return s;
  }
  if (tags.includes("circle_aoe_zone")) {
    const s = skills.find((x) => String(x.skillId || "").includes("ring") || String(x.skillId || "").includes("nova"));
    if (s) return s;
  }
  return skills[0];
}

function simulateWave(runtime, waveObj, heroes) {
  const boss = (runtime.boss.bosses || []).find((b) => b.id === waveObj.bossId) || {};
  const bossBehavior = (runtime.boss.bossBehavior21 || []).find((x) => x.bossId === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const tags = terrain.template.tags || [];
  const heroSpawns = terrain.instance.heroSpawnPoints || [];

  let bossHp = Math.max(1, Number(boss.baseHp || 5000));
  let teamHp = heroes.map(() => 2200);
  const turns = [];

  for (let turn = 1; turn <= 12; turn++) {
    let heroDmgTotal = 0;
    const heroCasts = [];
    for (let i = 0; i < heroes.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(heroes[i], tags);
      const role = String(action?.role || "dps_cycle");
      let dmg = roleBaseDamage(role);
      const pos = heroSpawns[i] || { x: 25, y: 50 };
      const risk = estimatePositionRisk(pos, terrain.instance, tags);
      const offenseMul = 1 / Math.max(0.85, Math.min(1.2, risk));
      dmg = Math.floor(dmg * offenseMul);
      if (tags.includes("open_arena")) dmg = Math.floor(dmg * 1.05);
      if (tags.includes("outer_ring_pathing") && role === "dps_sustain") dmg = Math.floor(dmg * 1.08);
      if (tags.includes("edge_hugging")) dmg = Math.floor(dmg * 0.93);
      heroDmgTotal += dmg;
      heroCasts.push({
        heroId: heroes[i].heroId,
        heroName: heroes[i].heroName,
        actionId: action?.actionId || "none",
        role,
        estRisk: Number(risk.toFixed(2)),
        damage: dmg
      });
    }

    bossHp = Math.max(0, bossHp - heroDmgTotal);
    const bossSkill = chooseBossSkill(bossBehavior, tags);
    const bossDmg = bossSkillDamage(bossSkill.skillId, tags);

    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      const pos = heroSpawns[i] || { x: 25, y: 50 };
      const risk = estimatePositionRisk(pos, terrain.instance, tags);
      const taken = Math.floor(bossDmg * risk);
      teamHp[i] = Math.max(0, teamHp[i] - taken);
    }

    turns.push({
      turn,
      heroTurnDamage: heroDmgTotal,
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
      spawnCount: heroSpawns.length,
      warningZoneCount: (terrain.instance.warningZones || []).length,
      blockerCount: (terrain.instance.blockers || []).length,
      safeZoneCount: (terrain.instance.safeZones || []).length
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
      version: "1.0-sim-v3",
      generatedAt: "2026-03-10",
      mapId: 180750,
      terrainInstanceAware: true,
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

  fs.writeFileSync("battle_replay_v3.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v3.json generated");
  console.log("SIM_V3_SUMMARY", replay.summary);
}

main();
