const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function mapByWave(replay) {
  const m = {};
  for (const w of replay.waveReplays || []) m[w.wave] = w;
  return m;
}

function teamIds(w) {
  return (w?.selectedTeam || []).map((x) => x.heroId).join(",");
}

function main() {
  const v9 = readJson("battle_replay_v9_adaptive.json");
  const v10 = readJson("battle_replay_v10_dual_plan.json");
  const m9 = mapByWave(v9);
  const m10 = mapByWave(v10);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m9[w];
    const b = m10[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV9: a.result,
      resultV10: b.result,
      bossHpLeftV9: a.bossHpLeft,
      bossHpLeftV10: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      teamChanged: teamIds(a) !== teamIds(b)
    });
  }

  const out = {
    meta: { version: "1.0-compare-v9-v10", generatedAt: "2026-03-10" },
    summary: {
      winsV9: v9.summary?.wins || 0,
      winsV10: v10.summary?.wins || 0,
      winDelta: (v10.summary?.wins || 0) - (v9.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV9 === "lose" && x.resultV10 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV9 === "win" && x.resultV10 === "lose").map((x) => x.wave),
      teamChangedWaves: rows.filter((x) => x.teamChanged).map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v9_v10.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v9_v10.json generated");
  console.log("COMPARE_V9_V10_SUMMARY", out.summary);
}

main();
