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
  const v3 = readJson("battle_replay_v3.json");
  const v4 = readJson("battle_replay_v4.json");
  const m3 = mapByWave(v3);
  const m4 = mapByWave(v4);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m3[w];
    const b = m4[w];
    if (!a || !b) continue;
    const t3 = (a.turns || []).length;
    const t4 = (b.turns || []).length;
    const d3 = (a.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    const d4 = (b.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    rows.push({
      wave: w,
      resultV3: a.result,
      resultV4: b.result,
      turnsV3: t3,
      turnsV4: t4,
      turnDelta: t4 - t3,
      heroDamageV3: d3,
      heroDamageV4: d4,
      heroDamageDelta: d4 - d3,
      bossHpLeftV3: a.bossHpLeft,
      bossHpLeftV4: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      terrainId: b.terrain?.terrainId || "unknown",
      deniedActions: b.terrain?.deniedActions || []
    });
  }

  const out = {
    meta: { version: "1.0-compare-v3-v4", generatedAt: "2026-03-10" },
    summary: {
      winsV3: v3.summary?.wins || 0,
      winsV4: v4.summary?.wins || 0,
      winDelta: (v4.summary?.wins || 0) - (v3.summary?.wins || 0),
      changedByTurns: rows.filter((x) => x.turnDelta !== 0).map((x) => x.wave),
      changedByDamage: rows.filter((x) => x.heroDamageDelta !== 0).map((x) => x.wave),
      improvedWaves: rows.filter((x) => x.resultV3 === "lose" && x.resultV4 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV3 === "win" && x.resultV4 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v3_v4.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v3_v4.json generated");
  console.log("COMPARE_V3_V4_SUMMARY", out.summary);
}

main();
