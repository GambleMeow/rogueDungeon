const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function terrainForWave(runtime, wave) {
  const tw = runtime.terrain?.waves || [];
  const templates = runtime.terrain?.templates || [];
  const tMap = {};
  for (const t of templates) tMap[t.terrainId] = t;
  const row = tw.find((x) => Number(x.wave) === Number(wave));
  const pool = row?.terrainPool || [];
  const terrainId = pool.length > 0 ? pool[wave % pool.length] : "arena_open";
  return tMap[terrainId] || { terrainId, name: terrainId, tags: [] };
}

function terrainCoef(id) {
  const m = {
    arena_open: { heroDmgMul: 1.12, bossDmgMul: 0.93 },
    arena_outer_ring: { heroDmgMul: 1.09, bossDmgMul: 0.9 },
    arena_edge_risky: { heroDmgMul: 0.9, bossDmgMul: 1.13 },
    arena_line_skill: { heroDmgMul: 0.94, bossDmgMul: 1.1 },
    arena_fan_facing: { heroDmgMul: 0.96, bossDmgMul: 1.08 },
    arena_circle_warning: { heroDmgMul: 0.93, bossDmgMul: 1.1 },
    arena_random_reposition: { heroDmgMul: 0.9, bossDmgMul: 1.12 },
    arena_stack_spread_switch: { heroDmgMul: 1.0, bossDmgMul: 1.02 }
  };
  return m[id] || { heroDmgMul: 1, bossDmgMul: 1 };
}

function roleBaseDamage(role) {
  const m = { burst: 238, dps_sustain: 173, dps_cycle: 163, board_control: 140, control: 132, survival: 106 };
  return m[role] || 148;
}

function parseBossTags(runtime, bossId) {
  const b = (runtime.boss.bossBehavior21 || []).find((x) => x.bossId === bossId);
  const txt = (b?.skills || []).map((s) => String(s.skillId || "")).join("|");
  const tags = [];
  if (txt.includes("charge") || txt.includes("burst")) tags.push("burst_pressure");
  if (txt.includes("ring") || txt.includes("nova")) tags.push("zone_pressure");
  if (txt.includes("reposition")) tags.push("reposition_pressure");
  if (txt.includes("summon")) tags.push("summon_pressure");
  return tags;
}

function heroFlags(hero) {
  return hero.behaviorFlags || {};
}

function scoreHero(hero, terrainTags, bossTags, state) {
  const f = heroFlags(hero);
  let s = 0;
  s += Math.min(8, Number(hero.guideCount || 0));
  if (terrainTags.includes("movement_check") && f.move) s += 10;
  if (terrainTags.includes("line_skill_lane") && f.move) s += 8;
  if (terrainTags.includes("circle_aoe_zone") && f.defense) s += 8;
  if (terrainTags.includes("fan_aoe_facing") && f.control) s += 8;
  if (terrainTags.includes("spread_requirement") && f.summon) s -= 8;
  if (bossTags.includes("burst_pressure") && f.defense) s += 9;
  if (bossTags.includes("zone_pressure") && f.defense) s += 8;
  if (bossTags.includes("reposition_pressure") && f.move) s += 8;
  if (bossTags.includes("summon_pressure") && f.control) s += 6;
  const fatigue = Number(state.heroUsage[hero.heroId] || 0);
  s -= fatigue * 2.8;
  if (state.lastFailedTeam.has(hero.heroId)) s -= 4;
  return s;
}

function chooseAdaptiveTeam(heroes, terrainTags, bossTags, state) {
  const scored = heroes
    .map((h) => ({ hero: h, score: scoreHero(h, terrainTags, bossTags, state) }))
    .sort((a, b) => b.score - a.score);

  const out = [];
  let needDefense = bossTags.includes("burst_pressure") || bossTags.includes("zone_pressure");
  let needMove = terrainTags.includes("movement_check") || bossTags.includes("reposition_pressure");

  for (const it of scored) {
    if (out.length >= 4) break;
    const h = it.hero;
    const f = heroFlags(h);
    if (needDefense && f.defense) {
      out.push(h);
      needDefense = false;
      continue;
    }
    if (needMove && f.move) {
      out.push(h);
      needMove = false;
    }
  }

  for (const it of scored) {
    if (out.length >= 4) break;
    if (!out.includes(it.hero)) out.push(it.hero);
  }
  return out.slice(0, 4);
}

function pickAction(hero) {
  const arr = hero.actionBindings || [];
  if (arr.length === 0) return null;
  return arr.reduce((a, b) => ((b.priority || 0) > (a.priority || 0) ? b : a), arr[0]);
}

function bossSkillId(runtime, bossId) {
  const b = (runtime.boss.bossBehavior21 || []).find((x) => x.bossId === bossId);
  const s = b?.skills || [];
  return s[0]?.skillId || "unknown";
}

function bossSkillDamage(skillId, terrainTags, coef, bossScale) {
  let d = 110;
  const id = String(skillId || "");
  if (id.includes("charge") || id.includes("burst")) d = 155;
  if (id.includes("ring") || id.includes("nova")) d = 134;
  if (terrainTags.includes("line_skill_lane")) d = Math.floor(d * 1.08);
  if (terrainTags.includes("circle_aoe_zone")) d = Math.floor(d * 1.08);
  return Math.floor(d * coef.bossDmgMul * bossScale);
}

function teamDamageBonus(team, terrainTags, bossTags) {
  let mul = 1.0;
  let defense = 0;
  let control = 0;
  let move = 0;
  for (const h of team) {
    const f = heroFlags(h);
    if (f.defense) defense += 1;
    if (f.control) control += 1;
    if (f.move) move += 1;
  }
  if (terrainTags.includes("spread_requirement") && move >= 2) mul *= 1.06;
  if (terrainTags.includes("circle_aoe_zone") && defense >= 2) mul *= 1.05;
  if (bossTags.includes("summon_pressure") && control >= 2) mul *= 1.05;
  return { heroMul: mul, takenMul: defense >= 2 ? 0.94 : 1.0 };
}

function simulateWave(runtime, waveObj, team, state) {
  const boss = (runtime.boss.bosses || []).find((x) => x.id === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const terrainTags = terrain.tags || [];
  const bossTags = parseBossTags(runtime, waveObj.bossId);
  const coef = terrainCoef(terrain.terrainId);
  const bonus = teamDamageBonus(team, terrainTags, bossTags);

  const waveIndex = Number(waveObj.wave);
  const econGrowth = 1 + (waveIndex - 1) * 0.04;
  const streakGrowth = 1 + state.winStreak * 0.03;
  const catchup = state.lastLose ? 1.1 : 1.0;
  const replanningBoost = state.replanCount > 0 ? 1 + Math.min(0.06, state.replanCount * 0.02) : 1.0;

  const heroDmgScale = econGrowth * streakGrowth * catchup * replanningBoost * bonus.heroMul;
  const heroHpScale = (1 + (waveIndex - 1) * 0.03) * (1 + state.winStreak * 0.02) * (state.lastLose ? 1.07 : 1);
  const bossScale = 1 + (waveIndex - 1) * 0.0175;

  let bossHp = Math.max(1, Math.floor(Number(boss.baseHp || 5000) * bossScale));
  let teamHp = team.map(() => Math.floor(2350 * heroHpScale));
  const turns = [];

  for (let turn = 1; turn <= 16; turn++) {
    let heroTurnDamage = 0;
    const heroCasts = [];
    for (let i = 0; i < team.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(team[i]);
      const role = String(action?.role || "dps_cycle");
      const dmg = Math.floor(roleBaseDamage(role) * heroDmgScale * coef.heroDmgMul);
      heroTurnDamage += dmg;
      heroCasts.push({
        heroId: team[i].heroId,
        heroName: team[i].heroName,
        actionId: action?.actionId || "none",
        role,
        damage: dmg
      });
    }

    bossHp = Math.max(0, bossHp - heroTurnDamage);
    const bSkill = bossSkillId(runtime, waveObj.bossId);
    const bDmg = bossSkillDamage(bSkill, terrainTags, coef, bossScale);
    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      teamHp[i] = Math.max(0, teamHp[i] - Math.floor(bDmg * bonus.takenMul));
    }

    turns.push({
      turn,
      heroTurnDamage,
      bossSkillId: bSkill,
      bossDamageBase: bDmg,
      bossHpAfterTurn: bossHp,
      teamHpAfterTurn: [...teamHp],
      heroCasts
    });
    const alive = teamHp.filter((x) => x > 0).length;
    if (bossHp <= 0 || alive === 0) break;
  }

  const alive = teamHp.filter((x) => x > 0).length;
  const win = bossHp <= 0 && alive > 0;
  return {
    wave: waveObj.wave,
    bossId: waveObj.bossId,
    bossName: boss.name || waveObj.bossId,
    selectedTeam: team.map((h) => ({ heroId: h.heroId, heroName: h.heroName, archetype: h.combatArchetype })),
    terrain: { terrainId: terrain.terrainId || "unknown", name: terrain.name || "unknown", tags: terrainTags },
    campaignScale: {
      heroDmgScale: Number(heroDmgScale.toFixed(3)),
      heroHpScale: Number(heroHpScale.toFixed(3)),
      bossScale: Number(bossScale.toFixed(3)),
      winStreak: state.winStreak,
      catchup: state.lastLose
    },
    result: win ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: alive,
    turns
  };
}

function updateStateAfterWave(state, waveReplay) {
  const teamIds = new Set((waveReplay.selectedTeam || []).map((x) => x.heroId));
  if (waveReplay.result === "win") {
    state.winStreak = Math.min(6, state.winStreak + 1);
    state.lastLose = false;
    state.replanCount = 0;
    state.lastFailedTeam = new Set();
  } else {
    state.winStreak = 0;
    state.lastLose = true;
    state.replanCount += 1;
    state.lastFailedTeam = teamIds;
  }
  for (const h of teamIds) {
    state.heroUsage[h] = Number(state.heroUsage[h] || 0) + 1;
  }
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = runtime.hero.heroes || [];
  const waves = runtime.boss.waves || [];

  const replay = {
    meta: {
      version: "1.0-sim-v9-adaptive",
      generatedAt: "2026-03-10",
      mapId: 180750,
      adaptiveTeamPool: true,
      failReplan: true
    },
    waveReplays: []
  };

  const state = {
    winStreak: 0,
    lastLose: false,
    replanCount: 0,
    heroUsage: {},
    lastFailedTeam: new Set()
  };

  let wins = 0;
  for (const w of waves) {
    const terrain = terrainForWave(runtime, w.wave);
    const terrainTags = terrain.tags || [];
    const bossTags = parseBossTags(runtime, w.bossId);
    const team = chooseAdaptiveTeam(heroes, terrainTags, bossTags, state);
    const r = simulateWave(runtime, w, team, state);
    replay.waveReplays.push(r);
    if (r.result === "win") wins += 1;
    updateStateAfterWave(state, r);
  }

  replay.summary = { totalWaves: waves.length, wins, losses: waves.length - wins, clearAll: wins === waves.length };
  fs.writeFileSync("battle_replay_v9_adaptive.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v9_adaptive.json generated");
  console.log("SIM_V9_SUMMARY", replay.summary);
}

main();
