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
    arena_open: { heroDmgMul: 1.14, bossDmgMul: 0.91 },
    arena_outer_ring: { heroDmgMul: 1.11, bossDmgMul: 0.88 },
    arena_edge_risky: { heroDmgMul: 0.93, bossDmgMul: 1.09 },
    arena_line_skill: { heroDmgMul: 0.96, bossDmgMul: 1.07 },
    arena_fan_facing: { heroDmgMul: 0.98, bossDmgMul: 1.05 },
    arena_circle_warning: { heroDmgMul: 0.96, bossDmgMul: 1.07 },
    arena_random_reposition: { heroDmgMul: 0.94, bossDmgMul: 1.08 },
    arena_stack_spread_switch: { heroDmgMul: 1.03, bossDmgMul: 0.99 }
  };
  return m[id] || { heroDmgMul: 1, bossDmgMul: 1 };
}

function roleBaseDamage(role) {
  const m = { burst: 246, dps_sustain: 180, dps_cycle: 170, board_control: 146, control: 138, survival: 112 };
  return m[role] || 152;
}

function flags(hero) {
  return hero.behaviorFlags || {};
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

function scoreHero(hero, terrainTags, bossTags, state, wave) {
  const f = flags(hero);
  let s = 0;
  s += Math.min(8, Number(hero.guideCount || 0));
  if (terrainTags.includes("movement_check") && f.move) s += 10;
  if (terrainTags.includes("line_skill_lane") && f.move) s += 8;
  if (terrainTags.includes("circle_aoe_zone") && f.defense) s += 9;
  if (terrainTags.includes("fan_aoe_facing") && f.control) s += 8;
  if (terrainTags.includes("random_reposition_pressure") && f.move) s += 10;
  if (terrainTags.includes("spread_requirement") && f.summon) s -= 8;
  if (bossTags.includes("burst_pressure") && f.defense) s += 9;
  if (bossTags.includes("zone_pressure") && f.defense) s += 8;
  if (bossTags.includes("reposition_pressure") && f.move) s += 9;
  if (bossTags.includes("summon_pressure") && f.control) s += 7;
  s -= Number(state.heroUsage[hero.heroId] || 0) * 2.1;
  if (state.lastFailedTeam.has(hero.heroId)) s -= 3;
  if (wave >= 16 && f.defense) s += 4;
  if (wave >= 16 && f.move) s += 3;
  return s;
}

function chooseTeam(heroes, terrainTags, bossTags, state, wave) {
  const ranked = heroes
    .map((h) => ({ hero: h, score: scoreHero(h, terrainTags, bossTags, state, wave) }))
    .sort((a, b) => b.score - a.score);
  const out = [];

  if (wave >= 16) {
    for (const it of ranked) {
      if (out.length >= 1) break;
      if (flags(it.hero).defense) out.push(it.hero);
    }
    for (const it of ranked) {
      if (out.length >= 2) break;
      if (flags(it.hero).move && !out.includes(it.hero)) out.push(it.hero);
    }
  }

  for (const it of ranked) {
    if (out.length >= 4) break;
    if (!out.includes(it.hero)) out.push(it.hero);
  }

  if (terrainTags.includes("random_reposition_pressure")) {
    const summoners = out.filter((h) => String(h.combatArchetype) === "summoner");
    if (summoners.length >= 2) {
      for (const it of ranked) {
        if (out.length < 4) break;
        if (out.includes(it.hero)) continue;
        if (String(it.hero.combatArchetype) !== "summoner") {
          const idx = out.findIndex((h) => String(h.combatArchetype) === "summoner");
          if (idx >= 0) out[idx] = it.hero;
          break;
        }
      }
    }
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
  if (terrainTags.includes("random_reposition_pressure")) d = Math.floor(d * 1.03);
  return Math.floor(d * coef.bossDmgMul * bossScale);
}

function teamBonus(team, terrainTags, bossTags, wave) {
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
  if (terrainTags.includes("circle_aoe_zone") && defense >= 2) mul *= 1.06;
  if (terrainTags.includes("random_reposition_pressure") && move >= 2) mul *= 1.08;
  if (bossTags.includes("summon_pressure") && control >= 2) mul *= 1.05;
  if (wave >= 16 && defense >= 1 && move >= 1) mul *= 1.05;
  const takenMul = defense >= 2 ? 0.9 : defense >= 1 ? 0.95 : 1.0;
  return { heroMul: mul, takenMul };
}

function endgameWaveBoost(wave, bossId, terrainTags) {
  if (wave < 16) return { dmg: 1, hp: 1 };
  let dmg = 1.04;
  let hp = 1.04;
  if (terrainTags.includes("random_reposition_pressure")) {
    dmg *= 1.06;
    hp *= 1.05;
  }
  if (bossId === "boss_18" || bossId === "boss_19" || bossId === "boss_20") {
    dmg *= 1.05;
    hp *= 1.04;
  }
  return { dmg, hp };
}

function simulateWave(runtime, waveObj, team, state) {
  const wave = Number(waveObj.wave);
  const boss = (runtime.boss.bosses || []).find((x) => x.id === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const terrainTags = terrain.tags || [];
  const bossTags = parseBossTags(runtime, waveObj.bossId);
  const coef = terrainCoef(terrain.terrainId);
  const bonus = teamBonus(team, terrainTags, bossTags, wave);
  const endBoost = endgameWaveBoost(wave, waveObj.bossId, terrainTags);

  const econGrowth = 1 + (wave - 1) * 0.04;
  const streakGrowth = 1 + state.winStreak * 0.03;
  const catchup = state.lastLose ? 1.1 : 1.0;
  const replan = state.replanCount > 0 ? 1 + Math.min(0.08, state.replanCount * 0.025) : 1.0;
  const lateWaveAdapt = wave >= 12 ? 1 + (wave - 12) * 0.02 : 1.0;
  const losingChainAdapt = state.loseChain > 0 ? 1 + Math.min(0.08, state.loseChain * 0.03) : 1.0;

  const heroDmgScale = econGrowth * streakGrowth * catchup * replan * bonus.heroMul * lateWaveAdapt * losingChainAdapt * endBoost.dmg;
  const heroHpScale = (1 + (wave - 1) * 0.03) * (1 + state.winStreak * 0.02) * (state.lastLose ? 1.08 : 1) * (wave >= 12 ? 1.05 : 1) * endBoost.hp;
  const bossScale = 1 + (wave - 1) * 0.016;

  let bossHp = Math.max(1, Math.floor(Number(boss.baseHp || 5000) * bossScale));
  let teamHp = team.map(() => Math.floor(2450 * heroHpScale));
  const turns = [];

  for (let turn = 1; turn <= 17; turn++) {
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
    selectedTeam: team.map((h) => ({ heroId: h.heroId, heroName: h.heroName, archetype: h.combatArchetype })),
    terrain: { terrainId: terrain.terrainId || "unknown", name: terrain.name || "unknown", tags: terrainTags },
    result: win ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: alive,
    turns
  };
}

function updateState(state, waveReplay) {
  const teamIds = new Set((waveReplay.selectedTeam || []).map((x) => x.heroId));
  if (waveReplay.result === "win") {
    state.winStreak = Math.min(6, state.winStreak + 1);
    state.lastLose = false;
    state.replanCount = 0;
    state.loseChain = 0;
    state.lastFailedTeam = new Set();
  } else {
    state.winStreak = 0;
    state.lastLose = true;
    state.replanCount += 1;
    state.loseChain += 1;
    state.lastFailedTeam = teamIds;
  }
  for (const id of teamIds) state.heroUsage[id] = Number(state.heroUsage[id] || 0) + 1;
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = runtime.hero.heroes || [];
  const waves = runtime.boss.waves || [];

  const replay = {
    meta: { version: "1.0-sim-v13-endgame-targeted", generatedAt: "2026-03-10", mapId: 180750, endgameTargeted: true },
    waveReplays: []
  };

  const state = { winStreak: 0, lastLose: false, replanCount: 0, loseChain: 0, heroUsage: {}, lastFailedTeam: new Set() };
  let wins = 0;

  for (const w of waves) {
    const terrain = terrainForWave(runtime, w.wave);
    const terrainTags = terrain.tags || [];
    const bossTags = parseBossTags(runtime, w.bossId);
    const team = chooseTeam(heroes, terrainTags, bossTags, state, Number(w.wave));
    const r = simulateWave(runtime, w, team, state);
    replay.waveReplays.push(r);
    if (r.result === "win") wins += 1;
    updateState(state, r);
  }

  replay.summary = { totalWaves: waves.length, wins, losses: waves.length - wins, clearAll: wins === waves.length };
  fs.writeFileSync("battle_replay_v13_endgame_targeted.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v13_endgame_targeted.json generated");
  console.log("SIM_V13_SUMMARY", replay.summary);
}

main();
