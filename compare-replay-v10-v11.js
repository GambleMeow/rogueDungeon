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
  const v10 = readJson("battle_replay_v10_dual_plan.json");
  const v11 = readJson("battle_replay_v11_multi_attempt.json");
  const m10 = mapByWave(v10);
  const m11 = mapByWave(v11);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m10[w];
    const b = m11[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV10: a.result,
      resultV11: b.result,
      bossHpLeftV10: a.bossHpLeft,
      bossHpLeftV11: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      planModeV11: b.planMode || "unknown"
    });
  }

  const out = {
    meta: { version: "1.0-compare-v10-v11", generatedAt: "2026-03-10" },
    summary: {
      winsV10: v10.summary?.wins || 0,
      winsV11: v11.summary?.wins || 0,
      winDelta: (v11.summary?.wins || 0) - (v10.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV10 === "lose" && x.resultV11 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV10 === "win" && x.resultV11 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v10_v11.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v10_v11.json generated");
  console.log("COMPARE_V10_V11_SUMMARY", out.summary);
}

main();
