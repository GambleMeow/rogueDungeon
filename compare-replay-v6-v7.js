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
  const v6 = readJson("battle_replay_v6.json");
  const v7 = readJson("battle_replay_v7_campaign.json");
  const m6 = mapByWave(v6);
  const m7 = mapByWave(v7);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m6[w];
    const b = m7[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV6: a.result,
      resultV7: b.result,
      bossHpLeftV6: a.bossHpLeft,
      bossHpLeftV7: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft
    });
  }

  const out = {
    meta: { version: "1.0-compare-v6-v7", generatedAt: "2026-03-10" },
    summary: {
      winsV6: v6.summary?.wins || 0,
      winsV7: v7.summary?.wins || 0,
      winDelta: (v7.summary?.wins || 0) - (v6.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV6 === "lose" && x.resultV7 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV6 === "win" && x.resultV7 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v6_v7.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v6_v7.json generated");
  console.log("COMPARE_V6_V7_SUMMARY", out.summary);
}

main();
