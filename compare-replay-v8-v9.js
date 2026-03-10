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
  const v8 = readJson("battle_replay_v8_progression.json");
  const v9 = readJson("battle_replay_v9_adaptive.json");
  const m8 = mapByWave(v8);
  const m9 = mapByWave(v9);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m8[w];
    const b = m9[w];
    if (!a || !b) continue;
    rows.push({
      wave: w,
      resultV8: a.result,
      resultV9: b.result,
      bossHpLeftV8: a.bossHpLeft,
      bossHpLeftV9: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      teamChanged: teamIds(a) !== teamIds(b)
    });
  }

  const out = {
    meta: { version: "1.0-compare-v8-v9", generatedAt: "2026-03-10" },
    summary: {
      winsV8: v8.summary?.wins || 0,
      winsV9: v9.summary?.wins || 0,
      winDelta: (v9.summary?.wins || 0) - (v8.summary?.wins || 0),
      improvedWaves: rows.filter((x) => x.resultV8 === "lose" && x.resultV9 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV8 === "win" && x.resultV9 === "lose").map((x) => x.wave),
      teamChangedWaves: rows.filter((x) => x.teamChanged).map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v8_v9.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v8_v9.json generated");
  console.log("COMPARE_V8_V9_SUMMARY", out.summary);
}

main();
