const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function indexByWave(replay) {
  const map = {};
  for (const w of replay.waveReplays || []) {
    map[w.wave] = w;
  }
  return map;
}

function main() {
  const v1 = readJson("battle_replay_v1.json");
  const v2 = readJson("battle_replay_v2.json");
  const m1 = indexByWave(v1);
  const m2 = indexByWave(v2);

  const waveDiffs = [];
  for (let wave = 1; wave <= 21; wave++) {
    const a = m1[wave];
    const b = m2[wave];
    if (!a || !b) continue;
    const turnsV1 = (a.turns || []).length;
    const turnsV2 = (b.turns || []).length;
    const totalHeroDamageV1 = (a.turns || []).reduce((s, t) => s + Number(t.heroTurnDamage || 0), 0);
    const totalHeroDamageV2 = (b.turns || []).reduce((s, t) => s + Number(t.heroTurnDamage || 0), 0);
    const avgBossDmgV1 =
      turnsV1 > 0
        ? Number(
            (
              (a.turns || []).reduce((s, t) => s + Number(t.bossDamagePerAliveHero || 0), 0) / turnsV1
            ).toFixed(2)
          )
        : 0;
    const avgBossDmgV2 =
      turnsV2 > 0
        ? Number(
            (
              (b.turns || []).reduce((s, t) => s + Number(t.bossDamagePerAliveHero || 0), 0) / turnsV2
            ).toFixed(2)
          )
        : 0;

    waveDiffs.push({
      wave,
      resultV1: a.result,
      resultV2: b.result,
      bossHpLeftV1: a.bossHpLeft,
      bossHpLeftV2: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      aliveV1: a.aliveHeroes,
      aliveV2: b.aliveHeroes,
      turnsV1,
      turnsV2,
      turnDelta: turnsV2 - turnsV1,
      totalHeroDamageV1,
      totalHeroDamageV2,
      heroDamageDelta: totalHeroDamageV2 - totalHeroDamageV1,
      avgBossDmgV1,
      avgBossDmgV2,
      avgBossDmgDelta: Number((avgBossDmgV2 - avgBossDmgV1).toFixed(2)),
      terrain: b.terrain
    });
  }

  const changedByTurns = waveDiffs.filter((x) => x.turnDelta !== 0).map((x) => x.wave);
  const changedByDamage = waveDiffs.filter((x) => x.heroDamageDelta !== 0 || x.avgBossDmgDelta !== 0).map((x) => x.wave);

  const summary = {
    winsV1: v1.summary?.wins || 0,
    winsV2: v2.summary?.wins || 0,
    winDelta: (v2.summary?.wins || 0) - (v1.summary?.wins || 0),
    improvedWaves: waveDiffs.filter((x) => x.resultV1 === "lose" && x.resultV2 === "win").map((x) => x.wave),
    regressedWaves: waveDiffs.filter((x) => x.resultV1 === "win" && x.resultV2 === "lose").map((x) => x.wave),
    changedByTurns,
    changedByDamage
  };

  const out = {
    meta: {
      version: "1.0-compare-v1-v2",
      generatedAt: "2026-03-10"
    },
    summary,
    waveDiffs
  };

  fs.writeFileSync("battle_replay_compare_v1_v2.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v1_v2.json generated");
  console.log("COMPARE_SUMMARY", summary);
}

main();
