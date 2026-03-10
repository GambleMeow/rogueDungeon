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
  const v5 = readJson("battle_replay_v5.json");
  const v6 = readJson("battle_replay_v6.json");
  const m5 = mapByWave(v5);
  const m6 = mapByWave(v6);

  const rows = [];
  for (let w = 1; w <= 21; w++) {
    const a = m5[w];
    const b = m6[w];
    if (!a || !b) continue;
    const t5 = (a.turns || []).length;
    const t6 = (b.turns || []).length;
    const d5 = (a.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    const d6 = (b.turns || []).reduce((s, x) => s + Number(x.heroTurnDamage || 0), 0);
    rows.push({
      wave: w,
      resultV5: a.result,
      resultV6: b.result,
      turnsV5: t5,
      turnsV6: t6,
      turnDelta: t6 - t5,
      heroDamageV5: d5,
      heroDamageV6: d6,
      heroDamageDelta: d6 - d5,
      bossHpLeftV5: a.bossHpLeft,
      bossHpLeftV6: b.bossHpLeft,
      bossHpDelta: b.bossHpLeft - a.bossHpLeft,
      teamChanged: teamIds(a) !== teamIds(b)
    });
  }

  const out = {
    meta: { version: "1.0-compare-v5-v6", generatedAt: "2026-03-10" },
    summary: {
      winsV5: v5.summary?.wins || 0,
      winsV6: v6.summary?.wins || 0,
      winDelta: (v6.summary?.wins || 0) - (v5.summary?.wins || 0),
      changedByTurns: rows.filter((x) => x.turnDelta !== 0).map((x) => x.wave),
      changedByDamage: rows.filter((x) => x.heroDamageDelta !== 0).map((x) => x.wave),
      improvedWaves: rows.filter((x) => x.resultV5 === "lose" && x.resultV6 === "win").map((x) => x.wave),
      regressedWaves: rows.filter((x) => x.resultV5 === "win" && x.resultV6 === "lose").map((x) => x.wave)
    },
    waveDiffs: rows
  };

  fs.writeFileSync("battle_replay_compare_v5_v6.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_v5_v6.json generated");
  console.log("COMPARE_V5_V6_SUMMARY", out.summary);
}

main();
