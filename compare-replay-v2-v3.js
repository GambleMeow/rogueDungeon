const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function mapByWave(replay) {
  const m = {};
  for (const w of replay.waveReplays || []) m[w.wave] = w;
  return m;
}

function main() {
  const v2 = readJson("battle_replay_v2.json");
  const v3 = readJson("battle_replay_v3.json");
  const m2 = mapByWave(v2);
  const m3 = mapByWave(v3);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m2[w];
    const b = m3[w];
    if (!a || !b) continue;
    const t2 = (a.turns || []).length;
    const t3 = (b.turns || []).length;
    const d2 = (a.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    const d3 = (b.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    rows.push({
      wave: w,
      resultV2: a.result,
      resultV3: b.result,
      turnsV2: t2,
      turnsV3: t3,
      turnDelta: t3 - t2,
      heroDamageV2: d2,
      heroDamageV3: d3,
      heroDamageDelta: d3 - d2,
      bossHpLeftV2: a.bossHpLeft,
      bossHpLeftV3: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      terrainId: b.terrain?.terrainId || "unknown"
    });
  }

  const out = {
    meta: { version: "1.0-compare-v2-v3", generatedAt: "2026-03-10" },
    summary: {
      winsV2: v2.summary?.wins || 0,
      winsV3: v3.summary?.wins || 0,
      winDelta: (v3.summary?.wins || 0) - (v2.summary?.wins || 0),
      changedByTurns: rows.filter((x) => x.turnDelta !== 0).map((x) => x.wave),
      changedByDamage: rows.filter((x) => x.heroDamageDelta !== 0).map((x) => x.wave),
      improvedWaves: rows.filter((x) => x.resultV2 === "lose" && x.resultV3 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV2 === "win" && x.resultV3 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v2_v3.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v2_v3.json generated");
  console.log("COMPARE_V2_V3_SUMMARY", out.summary);
}

main();
