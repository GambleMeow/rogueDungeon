const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function pickAction(hero) {
  const arr = hero.actionBindings || [];
  if (arr.length === 0) return null;
  let best = arr[0];
  for (const a of arr) {
    if ((a.priority || 0) > (best.priority || 0)) best = a;
  }
  return best;
}

function pickBossSkill(bossBehavior) {
  const skills = bossBehavior?.skills || [];
  if (skills.length === 0) return null;
  return skills[0];
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

function heroDamageFromAction(hero, action) {
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
  return Math.floor(base);
}

function bossDamageFromSkill(skill) {
  if (!skill) return 90;
  const id = String(skill.skillId || "");
  if (id.includes("burst") || id.includes("charge")) return 140;
  if (id.includes("taunt") || id.includes("control")) return 110;
  return 105;
}

function simulateWave(runtime, waveObj, heroes) {
  const bossId = waveObj.bossId;
  const boss = (runtime.boss.bosses || []).find((b) => b.id === bossId) || {};
  const bossBehavior = (runtime.boss.bossBehavior21 || []).find((b) => b.bossId === bossId) || {};
  const terrain = terrainForWave(runtime, waveObj.wave);

  let bossHp = Math.max(1, Number(boss.baseHp || 5000));
  let teamHp = heroes.map(() => 2000);
  const turnLog = [];

  for (let turn = 1; turn <= 12; turn++) {
    let heroTurnDamage = 0;
    const heroCasts = [];
    for (let i = 0; i < heroes.length; i++) {
      if (teamHp[i] <= 0) continue;
      const action = pickAction(heroes[i]);
      const dmg = heroDamageFromAction(heroes[i], action);
      heroTurnDamage += dmg;
      heroCasts.push({
        heroId: heroes[i].heroId,
        heroName: heroes[i].heroName,
        actionId: action?.actionId || "none",
        damage: dmg
      });
    }

    bossHp = Math.max(0, bossHp - heroTurnDamage);
    const bossSkill = pickBossSkill(bossBehavior);
    const bossDmg = bossDamageFromSkill(bossSkill);

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
      tags: terrain.tags || []
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
      version: "1.0-sim-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      heroTeam: heroes.map((h) => ({ heroId: h.heroId, heroName: h.heroName }))
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

  fs.writeFileSync("battle_replay_v1.json", JSON.stringify(replay, null, 2), "utf8");
  console.log("battle_replay_v1.json generated");
  console.log("SIM_SUMMARY", replay.summary);
}

main();
