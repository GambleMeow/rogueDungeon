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
    arena_stack_spread_switch: { heroDmgMul: 0.99, bossDmgMul: 1.03 }
  };
  return m[id] || { heroDmgMul: 1, bossDmgMul: 1 };
}

function roleBaseDamage(role) {
  const m = { burst: 235, dps_sustain: 170, dps_cycle: 160, board_control: 136, control: 128, survival: 102 };
  return m[role] || 145;
}

function chooseTeam(runtimeHeroes) {
  const sorted = [...runtimeHeroes].sort((a, b) => (b.guideCount || 0) - (a.guideCount || 0));
  return sorted.slice(0, 4);
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
  let d = 108;
  if (String(skillId).includes("charge") || String(skillId).includes("burst")) d = 150;
  if (String(skillId).includes("ring") || String(skillId).includes("nova")) d = 130;
  if (terrainTags.includes("line_skill_lane")) d = Math.floor(d * 1.08);
  if (terrainTags.includes("circle_aoe_zone")) d = Math.floor(d * 1.1);
  return Math.floor(d * coef.bossDmgMul * bossScale);
}

function simulateWave(runtime, waveObj, team, state) {
  const boss = (runtime.boss.bosses || []).find((x) => x.id === waveObj.bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const tags = terrain.tags || [];
  const coef = terrainCoef(terrain.terrainId);

  const waveIndex = Number(waveObj.wave);
  const econGrowth = 1 + (waveIndex - 1) * 0.04;
  const momentumGrowth = 1 + state.winStreak * 0.03;
  const catchup = state.lastLose ? 1.08 : 1.0;

  const heroDmgScale = econGrowth * momentumGrowth * catchup;
  const heroHpScale = (1 + (waveIndex - 1) * 0.03) * (1 + state.winStreak * 0.02) * (state.lastLose ? 1.06 : 1);
  const bossScale = 1 + (waveIndex - 1) * 0.018;

  let bossHp = Math.max(1, Math.floor(Number(boss.baseHp || 5000) * bossScale));
  let teamHp = team.map(() => Math.floor(2300 * heroHpScale));
  const turns = [];

  for (let turn = 1; turn <= 15; turn++) {
    let heroTurnDamage = 0;
    const heroCasts = [];
    for (let i = 0; i < team.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(team[i]);
      const role = String(action?.role || "dps_cycle");
      let dmg = roleBaseDamage(role);
      dmg = Math.floor(dmg * heroDmgScale * coef.heroDmgMul);
      heroTurnDamage += dmg;
      heroCasts.push({ heroId: team[i].heroId, heroName: team[i].heroName, actionId: action?.actionId || "none", role, damage: dmg });
    }

    bossHp = Math.max(0, bossHp - heroTurnDamage);
    const bSkill = bossSkillId(runtime, waveObj.bossId);
    const bDmg = bossSkillDamage(bSkill, tags, coef, bossScale);
    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      teamHp[i] = Math.max(0, teamHp[i] - bDmg);
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
    terrain: { terrainId: terrain.terrainId || "unknown", name: terrain.name || "unknown", tags },
    campaignScale: { heroDmgScale: Number(heroDmgScale.toFixed(3)), heroHpScale: Number(heroHpScale.toFixed(3)), bossScale: Number(bossScale.toFixed(3)), winStreak: state.winStreak, lastLose: state.lastLose },
    result: win ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: alive,
    turns
  };
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = runtime.hero.heroes || [];
  const team = chooseTeam(heroes);
  const waves = runtime.boss.waves || [];

  const replay = {
    meta: {
      version: "1.0-sim-v8-progression",
      generatedAt: "2026-03-10",
      mapId: 180750,
      progressionEnabled: true,
      fixedTeam: team.map((h) => ({ heroId: h.heroId, heroName: h.heroName }))
    },
    waveReplays: []
  };

  const state = { winStreak: 0, lastLose: false };
  let wins = 0;
  for (const w of waves) {
    const r = simulateWave(runtime, w, team, state);
    replay.waveReplays.push(r);
    if (r.result === "win") {
      wins += 1;
      state.winStreak = Math.min(5, state.winStreak + 1);
      state.lastLose = false;
    } else {
      state.winStreak = 0;
      state.lastLose = true;
    }
  }

  replay.summary = { totalWaves: waves.length, wins, losses: waves.length - wins, clearAll: wins === waves.length };
  fs.writeFileSync("battle_replay_v8_progression.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v8_progression.json generated");
  console.log("SIM_V8_SUMMARY", replay.summary);
}

main();
