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
    arena_open: { heroDmgMul: 1.13, bossDmgMul: 0.92 },
    arena_outer_ring: { heroDmgMul: 1.1, bossDmgMul: 0.89 },
    arena_edge_risky: { heroDmgMul: 0.91, bossDmgMul: 1.12 },
    arena_line_skill: { heroDmgMul: 0.95, bossDmgMul: 1.09 },
    arena_fan_facing: { heroDmgMul: 0.97, bossDmgMul: 1.07 },
    arena_circle_warning: { heroDmgMul: 0.94, bossDmgMul: 1.09 },
    arena_random_reposition: { heroDmgMul: 0.91, bossDmgMul: 1.11 },
    arena_stack_spread_switch: { heroDmgMul: 1.01, bossDmgMul: 1.01 }
  };
  return m[id] || { heroDmgMul: 1, bossDmgMul: 1 };
}

function roleBaseDamage(role) {
  const m = { burst: 242, dps_sustain: 176, dps_cycle: 166, board_control: 143, control: 135, survival: 109 };
  return m[role] || 150;
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

function flags(hero) {
  return hero.behaviorFlags || {};
}

function scoreHero(hero, terrainTags, bossTags, state) {
  const f = flags(hero);
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
  s -= Number(state.heroUsage[hero.heroId] || 0) * 2.2;
  if (state.lastFailedTeam.has(hero.heroId)) s -= 3;
  return s;
}

function rankHeroes(heroes, terrainTags, bossTags, state) {
  return heroes
    .map((h) => ({ hero: h, score: scoreHero(h, terrainTags, bossTags, state) }))
    .sort((a, b) => b.score - a.score);
}

function buildTeam(ranked, mode) {
  const out = [];
  if (mode === "defense_first") {
    for (const it of ranked) {
      if (out.length >= 2) break;
      if (flags(it.hero).defense) out.push(it.hero);
    }
  }
  if (mode === "mobility_first") {
    for (const it of ranked) {
      if (out.length >= 2) break;
      if (flags(it.hero).move) out.push(it.hero);
    }
  }
  for (const it of ranked) {
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
  let d = 114;
  const id = String(skillId || "");
  if (id.includes("charge") || id.includes("burst")) d = 158;
  if (id.includes("ring") || id.includes("nova")) d = 137;
  if (terrainTags.includes("line_skill_lane")) d = Math.floor(d * 1.08);
  if (terrainTags.includes("circle_aoe_zone")) d = Math.floor(d * 1.08);
  return Math.floor(d * coef.bossDmgMul * bossScale);
}

function teamBonus(team, terrainTags, bossTags) {
  let mul = 1.0;
  let defense = 0;
  let control = 0;
  let move = 0;
  for (const h of team) {
    const f = flags(h);
    if (f.defense) defense += 1;
    if (f.control) control += 1;
    if (f.move) move += 1;
  }
  if (terrainTags.includes("spread_requirement") && move >= 2) mul *= 1.06;
  if (terrainTags.includes("circle_aoe_zone") && defense >= 2) mul *= 1.05;
  if (bossTags.includes("summon_pressure") && control >= 2) mul *= 1.05;
  return { heroMul: mul, takenMul: defense >= 2 ? 0.92 : 0.98 };
}

function simulateWave(runtime, waveObj, team, state, modeName) {
  const boss = (runtime.boss.bosses || []).find((x) => x.id === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const terrainTags = terrain.tags || [];
  const bossTags = parseBossTags(runtime, waveObj.bossId);
  const coef = terrainCoef(terrain.terrainId);
  const bonus = teamBonus(team, terrainTags, bossTags);

  const waveIndex = Number(waveObj.wave);
  const econGrowth = 1 + (waveIndex - 1) * 0.04;
  const streakGrowth = 1 + state.winStreak * 0.03;
  const catchup = state.lastLose ? 1.1 : 1.0;
  const replan = state.replanCount > 0 ? 1 + Math.min(0.08, state.replanCount * 0.025) : 1.0;
  const modeBoost = modeName === "mobility_first" ? 1.02 : 1.0;

  const heroDmgScale = econGrowth * streakGrowth * catchup * replan * bonus.heroMul * modeBoost;
  const heroHpScale = (1 + (waveIndex - 1) * 0.03) * (1 + state.winStreak * 0.02) * (state.lastLose ? 1.08 : 1);
  const bossScale = 1 + (waveIndex - 1) * 0.0165;

  let bossHp = Math.max(1, Math.floor(Number(boss.baseHp || 5000) * bossScale));
  let teamHp = team.map(() => Math.floor(2400 * heroHpScale));
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
      heroCasts.push({ heroId: team[i].heroId, heroName: team[i].heroName, actionId: action?.actionId || "none", role, damage: dmg });
    }

    bossHp = Math.max(0, bossHp - heroTurnDamage);
    const bSkill = bossSkillId(runtime, waveObj.bossId);
    const bDmg = bossSkillDamage(bSkill, terrainTags, coef, bossScale);
    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      teamHp[i] = Math.max(0, teamHp[i] - Math.floor(bDmg * bonus.takenMul));
    }

    turns.push({ turn, heroTurnDamage, bossSkillId: bSkill, bossDamageBase: bDmg, bossHpAfterTurn: bossHp, teamHpAfterTurn: [...teamHp], heroCasts });
    const alive = teamHp.filter((x) => x > 0).length;
    if (bossHp <= 0 || alive === 0) break;
  }

  const alive = teamHp.filter((x) => x > 0).length;
  const win = bossHp <= 0 && alive > 0;
  return {
    wave: waveObj.wave,
    bossId: waveObj.bossId,
    bossName: boss.name || waveObj.bossId,
    planMode: modeName,
    selectedTeam: team.map((h) => ({ heroId: h.heroId, heroName: h.heroName, archetype: h.combatArchetype })),
    terrain: { terrainId: terrain.terrainId || "unknown", name: terrain.name || "unknown", tags: terrainTags },
    result: win ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: alive,
    turns
  };
}

function betterReplay(a, b) {
  if (a.result !== b.result) return a.result === "win" ? a : b;
  if (a.result === "win") {
    const tA = (a.turns || []).length;
    const tB = (b.turns || []).length;
    return tA <= tB ? a : b;
  }
  return a.bossHpLeft <= b.bossHpLeft ? a : b;
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
  for (const id of teamIds) {
    state.heroUsage[id] = Number(state.heroUsage[id] || 0) + 1;
  }
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = runtime.hero.heroes || [];
  const waves = runtime.boss.waves || [];

  const replay = {
    meta: {
      version: "1.0-sim-v11-multi-attempt",
      generatedAt: "2026-03-10",
      mapId: 180750,
      adaptiveTeamPool: true,
      dualAttemptPerWave: true
    },
    waveReplays: []
  };

  const state = { winStreak: 0, lastLose: false, replanCount: 0, heroUsage: {}, lastFailedTeam: new Set() };
  let wins = 0;

  for (const w of waves) {
    const terrain = terrainForWave(runtime, w.wave);
    const terrainTags = terrain.tags || [];
    const bossTags = parseBossTags(runtime, w.bossId);
    const ranked = rankHeroes(heroes, terrainTags, bossTags, state);
    const teamA = buildTeam(ranked, "defense_first");
    const teamB = buildTeam(ranked, "mobility_first");

    const attemptA = simulateWave(runtime, w, teamA, state, "defense_first");
    const attemptB = simulateWave(runtime, w, teamB, state, "mobility_first");
    const best = betterReplay(attemptA, attemptB);

    replay.waveReplays.push(best);
    if (best.result === "win") wins += 1;
    updateStateAfterWave(state, best);
  }

  replay.summary = { totalWaves: waves.length, wins, losses: waves.length - wins, clearAll: wins === waves.length };
  fs.writeFileSync("battle_replay_v11_multi_attempt.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v11_multi_attempt.json generated");
  console.log("SIM_V11_SUMMARY", replay.summary);
}

main();
