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
  const v7 = readJson("battle_replay_v7_campaign.json");
  const v8 = readJson("battle_replay_v8_progression.json");
  const m7 = mapByWave(v7);
  const m8 = mapByWave(v8);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m7[w];
    const b = m8[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV7: a.result,
      resultV8: b.result,
      bossHpLeftV7: a.bossHpLeft,
      bossHpLeftV8: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft
    });
  }

  const out = {
    meta: { version: "1.0-compare-v7-v8", generatedAt: "2026-03-10" },
    summary: {
      winsV7: v7.summary?.wins || 0,
      winsV8: v8.summary?.wins || 0,
      winDelta: (v8.summary?.wins || 0) - (v7.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV7 === "lose" && x.resultV8 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV7 === "win" && x.resultV8 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v7_v8.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v7_v8.json generated");
  console.log("COMPARE_V7_V8_SUMMARY", out.summary);
}

main();
