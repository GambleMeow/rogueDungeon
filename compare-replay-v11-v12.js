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
  const v11 = readJson("battle_replay_v11_multi_attempt.json");
  const v12 = readJson("battle_replay_v12_latewave_adapt.json");
  const m11 = mapByWave(v11);
  const m12 = mapByWave(v12);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m11[w];
    const b = m12[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV11: a.result,
      resultV12: b.result,
      bossHpLeftV11: a.bossHpLeft,
      bossHpLeftV12: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft
    });
  }

  const out = {
    meta: { version: "1.0-compare-v11-v12", generatedAt: "2026-03-10" },
    summary: {
      winsV11: v11.summary?.wins || 0,
      winsV12: v12.summary?.wins || 0,
      winDelta: (v12.summary?.wins || 0) - (v11.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV11 === "lose" && x.resultV12 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV11 === "win" && x.resultV12 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v11_v12.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v11_v12.json generated");
  console.log("COMPARE_V11_V12_SUMMARY", out.summary);
}

main();
