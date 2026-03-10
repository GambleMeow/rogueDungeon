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
  const v4 = readJson("battle_replay_v4.json");
  const v5 = readJson("battle_replay_v5.json");
  const m4 = mapByWave(v4);
  const m5 = mapByWave(v5);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m4[w];
    const b = m5[w];
    if (!a || !b) continue;
    const t4 = (a.turns || []).length;
    const t5 = (b.turns || []).length;
    const d4 = (a.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    const d5 = (b.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    rows.push({
      wave: w,
      resultV4: a.result,
      resultV5: b.result,
      turnsV4: t4,
      turnsV5: t5,
      turnDelta: t5 - t4,
      heroDamageV4: d4,
      heroDamageV5: d5,
      heroDamageDelta: d5 - d4,
      bossHpLeftV4: a.bossHpLeft,
      bossHpLeftV5: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      terrainId: b.terrain?.terrainId || "unknown",
      teamChanged: teamIds(a) !== teamIds(b),
      teamV5: teamIds(b)
    });
  }

  const out = {
    meta: { version: "1.0-compare-v4-v5", generatedAt: "2026-03-10" },
    summary: {
      winsV4: v4.summary?.wins || 0,
      winsV5: v5.summary?.wins || 0,
      winDelta: (v5.summary?.wins || 0) - (v4.summary?.wins || 0),
      changedByTurns: rows.filter((x) => x.turnDelta !== 0).map((x) => x.wave),
      changedByDamage: rows.filter((x) => x.heroDamageDelta !== 0).map((x) => x.wave),
      teamChangedWaves: rows.filter((x) => x.teamChanged).map((x) => x.wave),
      improvedWaves: rows.filter((x) => x.resultV4 === "lose" && x.resultV5 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV4 === "win" && x.resultV5 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v4_v5.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v4_v5.json generated");
  console.log("COMPARE_V4_V5_SUMMARY", out.summary);
}

main();
