const fs = require("fs");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function pickExisting(paths) {
  for (const p of paths) {
    if (fs.existsSync(p)) return p;
  }
  return "";
}

function addCount(mapObj, key, delta = 1) {
  if (!key) return;
  mapObj[key] = Number(mapObj[key] || 0) + delta;
}

function toMapFromNodeReplay(nodeReplay) {
  const rows = Array.isArray(nodeReplay)
    ? nodeReplay
    : nodeReplay.waveReplays || nodeReplay.rows || [];
  const m = new Map();
  for (const r of rows) {
    const wave = Number(r.wave || r.waveIndex || 0);
    if (!wave) continue;
    const heroActionCounts = {};
    const bossSkillCounts = {};
    const turns = Array.isArray(r.turns) ? r.turns : [];
    for (const t of turns) {
      for (const c of t.heroCasts || []) {
        addCount(heroActionCounts, String(c.actionId || "none"));
      }
      addCount(bossSkillCounts, String(t.bossSkillId || "none"));
    }
    m.set(wave, {
      result: String(r.result || "").toLowerCase(),
      turns: turns.length,
      boss: String(r.bossId || ""),
      heroActionCounts,
      bossSkillCounts
    });
  }
  return m;
}

function toMapFromGodotReplay(godotReplay) {
  const rows = godotReplay.waves || [];
  const m = new Map();
  for (const r of rows) {
    const wave = Number(r.wave || 0);
    if (!wave) continue;
    const heroActionCounts = {};
    const bossSkillCounts = {};
    if (r.heroActionCounts && typeof r.heroActionCounts === "object") {
      Object.assign(heroActionCounts, r.heroActionCounts);
    }
    if (r.bossSkillCounts && typeof r.bossSkillCounts === "object") {
      Object.assign(bossSkillCounts, r.bossSkillCounts);
    }
    if (Object.keys(heroActionCounts).length === 0 || Object.keys(bossSkillCounts).length === 0) {
      for (const t of r.ticks || []) {
        for (const a of t.heroActions || []) {
          addCount(heroActionCounts, String(a.actionId || "none"));
        }
        const ba = t.bossAction || {};
        addCount(bossSkillCounts, String(ba.skillId || "none"));
      }
    }
    m.set(wave, {
      result: String(r.result || "").toLowerCase(),
      elapsedSec: Number(r.elapsedSec || 0),
      boss: String(r.bossId || ""),
      heroActionCounts,
      bossSkillCounts
    });
  }
  return m;
}

function topDiffs(aCounts, bCounts, topN = 8) {
  const keys = [...new Set([...Object.keys(aCounts), ...Object.keys(bCounts)])];
  const rows = keys.map((k) => {
    const a = Number(aCounts[k] || 0);
    const b = Number(bCounts[k] || 0);
    return { key: k, node: a, godot: b, delta: b - a, absDelta: Math.abs(b - a) };
  });
  rows.sort((x, y) => y.absDelta - x.absDelta);
  return rows.slice(0, topN);
}

function main() {
  const nodePath =
    process.argv[2] ||
    pickExisting(["battle_replay_v14_runtime_driven.json", "battle_replay_v14_runtime-driven.json"]);
  const godotPath = process.argv[3] || pickExisting(["battle_replay_godot_v1.json"]);
  if (!fs.existsSync(nodePath)) {
    console.error("NODE_REPLAY_NOT_FOUND", nodePath);
    process.exit(1);
  }
  if (!fs.existsSync(godotPath)) {
    console.error("GODOT_REPLAY_NOT_FOUND", godotPath);
    process.exit(1);
  }

  const nodeReplay = readJson(nodePath);
  const godotReplay = readJson(godotPath);

  const nodeMap = toMapFromNodeReplay(nodeReplay);
  const godotMap = toMapFromGodotReplay(godotReplay);
  const waves = [...new Set([...nodeMap.keys(), ...godotMap.keys()])].sort((a, b) => a - b);

  const rows = [];
  let sameResult = 0;
  let compared = 0;
  const aggNodeAction = {};
  const aggGodotAction = {};
  const aggNodeSkill = {};
  const aggGodotSkill = {};
  for (const wave of waves) {
    const n = nodeMap.get(wave);
    const g = godotMap.get(wave);
    if (!n || !g) continue;
    compared += 1;
    const resultSame = n.result === g.result;
    if (resultSame) sameResult += 1;
    for (const [k, v] of Object.entries(n.heroActionCounts || {})) addCount(aggNodeAction, k, Number(v || 0));
    for (const [k, v] of Object.entries(g.heroActionCounts || {})) addCount(aggGodotAction, k, Number(v || 0));
    for (const [k, v] of Object.entries(n.bossSkillCounts || {})) addCount(aggNodeSkill, k, Number(v || 0));
    for (const [k, v] of Object.entries(g.bossSkillCounts || {})) addCount(aggGodotSkill, k, Number(v || 0));

    rows.push({
      wave,
      nodeResult: n.result,
      godotResult: g.result,
      sameResult: resultSame,
      nodeTurns: n.turns,
      godotElapsedSec: g.elapsedSec,
      bossNode: n.boss,
      bossGodot: g.boss,
      heroActionTopDiff: topDiffs(n.heroActionCounts || {}, g.heroActionCounts || {}, 5),
      bossSkillTopDiff: topDiffs(n.bossSkillCounts || {}, g.bossSkillCounts || {}, 5)
    });
  }

  const actionTopDiffGlobal = topDiffs(aggNodeAction, aggGodotAction, 12);
  const skillTopDiffGlobal = topDiffs(aggNodeSkill, aggGodotSkill, 12);

  const out = {
    meta: {
      version: "1.0-compare-replay-godot-v1",
      nodePath,
      godotPath,
      comparedWaves: compared,
      sameResultCount: sameResult,
      sameResultRate: compared > 0 ? Number((sameResult / compared).toFixed(4)) : 0
    },
    actionDiffGlobal: actionTopDiffGlobal,
    bossSkillDiffGlobal: skillTopDiffGlobal,
    rows
  };
  fs.writeFileSync("battle_replay_compare_godot_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("battle_replay_compare_godot_v1.json generated");
  console.log("COMPARE_GODOT_SUMMARY", out.meta);
}

main();
