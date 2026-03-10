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
  const v13 = readJson("battle_replay_v13_endgame_targeted.json");
  const v14 = readJson("battle_replay_v14_runtime_driven.json");
  const m13 = mapByWave(v13);
  const m14 = mapByWave(v14);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m13[w];
    const b = m14[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV13: a.result,
      resultV14: b.result,
      bossHpLeftV13: a.bossHpLeft,
      bossHpLeftV14: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft
    });
  }

  const out = {
    meta: { version: "1.0-compare-v13-v14", generatedAt: "2026-03-10" },
    summary: {
      winsV13: v13.summary?.wins || 0,
      winsV14: v14.summary?.wins || 0,
      winDelta: (v14.summary?.wins || 0) - (v13.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV13 === "lose" && x.resultV14 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV13 === "win" && x.resultV14 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v13_v14.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v13_v14.json generated");
  console.log("COMPARE_V13_V14_SUMMARY", out.summary);
}

main();
