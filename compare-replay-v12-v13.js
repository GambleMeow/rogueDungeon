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
  const v12 = readJson("battle_replay_v12_latewave_adapt.json");
  const v13 = readJson("battle_replay_v13_endgame_targeted.json");
  const m12 = mapByWave(v12);
  const m13 = mapByWave(v13);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m12[w];
    const b = m13[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV12: a.result,
      resultV13: b.result,
      bossHpLeftV12: a.bossHpLeft,
      bossHpLeftV13: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft
    });
  }

  const out = {
    meta: { version: "1.0-compare-v12-v13", generatedAt: "2026-03-10" },
    summary: {
      winsV12: v12.summary?.wins || 0,
      winsV13: v13.summary?.wins || 0,
      winDelta: (v13.summary?.wins || 0) - (v12.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV12 === "lose" && x.resultV13 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV12 === "win" && x.resultV13 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v12_v13.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v12_v13.json generated");
  console.log("COMPARE_V12_V13_SUMMARY", out.summary);
}

main();
