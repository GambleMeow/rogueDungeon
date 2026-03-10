const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function terrainForWave(runtime, wave) {
  const tw = runtime.terrain?.waves || [];
  const templates = runtime.terrain?.templates || [];
  const map = {};
  for (const t of templates) map[t.terrainId] = t;
  const row = tw.find((x) => Number(x.wave) === Number(wave));
  const pool = row?.terrainPool || [];
  const terrainId = pool.length > 0 ? pool[wave % pool.length] : "arena_open";
  return map[terrainId] || { terrainId, name: terrainId, tags: [] };
}

function terrainActionBonus(action, terrainTags) {
  const role = String(action?.role || "");
  const id = String(action?.actionId || "");
  const tags = terrainTags || [];
  let bonus = 0;

  if (tags.includes("movement_check") && role === "mobility") bonus += 18;
  if (tags.includes("movement_check") && role === "survival") bonus += 8;
  if (tags.includes("line_skill_lane") && role === "mobility") bonus += 12;
  if (tags.includes("fan_aoe_facing") && role === "control") bonus += 10;
  if (tags.includes("circle_aoe_zone") && role === "control") bonus += 10;
  if (tags.includes("spread_requirement") && role === "summon") bonus -= 8;
  if (tags.includes("stack_requirement") && role === "board_control") bonus += 6;
  if (tags.includes("anti_stuck_layout") && id === "mobility_reposition") bonus += 16;
  if (tags.includes("edge_hugging") && role === "mobility") bonus += 8;
  if (tags.includes("kite_and_pull") && id === "primary_pattern") bonus += 5;

  return bonus;
}

function terrainCoefficients(terrain) {
  const id = String(terrain?.terrainId || "");
  // heroDmgMul: party damage multiplier
  // bossDmgMul: boss damage multiplier
  const base = { heroDmgMul: 1.0, bossDmgMul: 1.0 };
  if (id === "arena_open") return { heroDmgMul: 1.08, bossDmgMul: 0.95 };
  if (id === "arena_outer_ring") return { heroDmgMul: 1.05, bossDmgMul: 0.92 };
  if (id === "arena_edge_risky") return { heroDmgMul: 0.92, bossDmgMul: 1.12 };
  if (id === "arena_line_skill") return { heroDmgMul: 0.95, bossDmgMul: 1.1 };
  if (id === "arena_fan_facing") return { heroDmgMul: 0.96, bossDmgMul: 1.08 };
  if (id === "arena_circle_warning") return { heroDmgMul: 0.94, bossDmgMul: 1.1 };
  if (id === "arena_random_reposition") return { heroDmgMul: 0.9, bossDmgMul: 1.12 };
  if (id === "arena_stack_spread_switch") return { heroDmgMul: 0.98, bossDmgMul: 1.04 };
  return base;
}

function pickAction(hero, terrainTags) {
  const arr = hero.actionBindings || [];
  if (arr.length === 0) return null;
  let best = null;
  let bestScore = -Infinity;
  for (const a of arr) {
    const base = Number(a.priority || 0);
    const score = base + terrainActionBonus(a, terrainTags);
    if (score > bestScore) {
      bestScore = score;
      best = a;
    }
  }
  return best;
}

function pickBossSkill(bossBehavior, terrainTags) {
  const skills = bossBehavior?.skills || [];
  if (skills.length === 0) return null;
  if (terrainTags.includes("anti_stuck_layout")) {
    const moveSkill = skills.find((s) => String(s.skillId || "").includes("reposition"));
    if (moveSkill) return moveSkill;
  }
  if (terrainTags.includes("circle_aoe_zone")) {
    const zoneSkill = skills.find((s) => {
      const id = String(s.skillId || "");
      return id.includes("ring") || id.includes("nova") || id.includes("burst");
    });
    if (zoneSkill) return zoneSkill;
  }
  return skills[0];
}

function heroDamageFromAction(hero, action, terrainTags, terrainCoef) {
  const archetype = hero.combatArchetype || "hybrid";
  const role = action?.role || "dps_sustain";
  let base = 120;
  if (archetype === "auto_attack") base = 160;
  if (archetype === "caster") base = 150;
  if (archetype === "summoner") base = 140;
  if (archetype === "hybrid") base = 145;
  if (role === "burst") base *= 1.45;
  if (role === "control") base *= 0.9;
  if (role === "survival") base *= 0.75;
  if (role === "board_control") base *= 0.95;

  // Terrain multipliers
  let terrainMul = 1.0;
  if (terrainTags.includes("open_arena")) terrainMul *= 1.05;
  if (terrainTags.includes("movement_check") && role === "mobility") terrainMul *= 1.1;
  if (terrainTags.includes("outer_ring_pathing") && role === "dps_sustain") terrainMul *= 1.06;
  if (terrainTags.includes("frontal_cone") && role === "dps_sustain") terrainMul *= 0.94;
  if (terrainTags.includes("circle_aoe_zone") && role === "survival") terrainMul *= 0.92;
  if (terrainTags.includes("anti_stuck_layout") && role === "mobility") terrainMul *= 1.08;

  return Math.floor(base * terrainMul * terrainCoef.heroDmgMul);
}

function bossDamageFromSkill(skill, terrainTags, terrainCoef) {
  if (!skill) return 90;
  const id = String(skill.skillId || "");
  let dmg = 105;
  if (id.includes("burst") || id.includes("charge")) dmg = 140;
  else if (id.includes("taunt") || id.includes("control")) dmg = 110;

  // Terrain pressure to team
  let mul = 1.0;
  if (terrainTags.includes("line_skill_lane")) mul *= 1.08;
  if (terrainTags.includes("fan_aoe_facing")) mul *= 1.06;
  if (terrainTags.includes("circle_aoe_zone")) mul *= 1.1;
  if (terrainTags.includes("edge_hugging")) mul *= 1.05;
  if (terrainTags.includes("open_arena")) mul *= 0.97;

  return Math.floor(dmg * mul * terrainCoef.bossDmgMul);
}

function simulateWave(runtime, waveObj, heroes) {
  const bossId = waveObj.bossId;
  const boss = (runtime.boss.bosses || []).find((b) => b.id === bossId) || {};
  const bossBehavior = (runtime.boss.bossBehavior21 || []).find((b) => b.bossId === bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);
  const terrainTags = terrain.tags || [];
  const terrainCoef = terrainCoefficients(terrain);

  let bossHp = Math.max(1, Number(boss.baseHp || 5000));
  let teamHp = heroes.map(() => 2000);
  const turnLog = [];

  for (let turn = 1; turn <= 12; turn++) {
    let heroTurnDamage = 0;
    const heroCasts = [];
    for (let i = 0; i < heroes.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(heroes[i], terrainTags);
      const dmg = heroDamageFromAction(heroes[i], action, terrainTags, terrainCoef);
      heroTurnDamage += dmg;
      heroCasts.push({
        heroId: heroes[i].heroId,
        heroName: heroes[i].heroName,
        actionId: action?.actionId || "none",
        damage: dmg
      });
    }

    bossHp = Math.max(0, bossHp - heroTurnDamage);
    const bossSkill = pickBossSkill(bossBehavior, terrainTags);
    const bossDmg = bossDamageFromSkill(bossSkill, terrainTags, terrainCoef);

    for (let i = 0; i < teamHp.length; i++) {
      if (teamHp[i] <= 0) continue;
      teamHp[i] = Math.max(0, teamHp[i] - bossDmg);
    }

    turnLog.push({
      turn,
      heroTurnDamage,
      bossSkillId: bossSkill?.skillId || "unknown",
      bossDamagePerAliveHero: bossDmg,
      bossHpAfterTurn: bossHp,
      teamHpAfterTurn: [...teamHp],
      heroCasts
    });

    const alive = teamHp.filter((x) => x > 0).length;
    if (bossHp <= 0 || alive === 0) break;
  }

  const aliveCount = teamHp.filter((x) => x > 0).length;
  const win = bossHp <= 0 && aliveCount > 0;

  return {
    wave: waveObj.wave,
    bossId,
    bossName: boss.name || bossId,
    terrain: {
      terrainId: terrain.terrainId || "unknown",
      name: terrain.name || "unknown",
      tags: terrainTags
    },
    result: win ? "win" : "lose",
    bossHpLeft: bossHp,
    aliveHeroes: aliveCount,
    turns: turnLog
  };
}

function main() {
  const bundle = readJson("runtime_bundle_v1.json");
  const runtime = bundle.runtime || {};
  const heroes = (runtime.hero.heroes || []).slice(0, 4);
  const waves = runtime.boss.waves || [];

  const replay = {
    meta: {
      version: "1.0-sim-v2",
      generatedAt: "2026-03-10",
      mapId: 180750,
      heroTeam: heroes.map((h) => ({ heroId: h.heroId, heroName: h.heroName })),
      terrainEnabled: true
    },
    waveReplays: []
  };

  let totalWins = 0;
  for (const w of waves) {
    const res = simulateWave(runtime, w, heroes);
    replay.waveReplays.push(res);
    if (res.result === "win") totalWins += 1;
  }

  replay.summary = {
    totalWaves: waves.length,
    wins: totalWins,
    losses: waves.length - totalWins,
    clearAll: totalWins === waves.length
  };

  fs.writeFileSync("battle_replay_v2.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v2.json generated");
  console.log("SIM_V2_SUMMARY", replay.summary);
}

main();
