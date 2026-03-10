const fs = require("fs");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

function pick(pathArg, fallback) {
  if (pathArg) return pathArg;
  return fallback;
}

function buildActionOverrides(actionDiffGlobal) {
  const out = {};
  for (const row of actionDiffGlobal || []) {
    const key = String(row.key || "");
    if (!key || key === "none") continue;
    const node = Number(row.node || 0);
    const godot = Number(row.godot || 0);
    if (node <= 0 && godot <= 0) continue;
    const deltaRatio = (godot - node) / Math.max(1, node);
    const adjust = clamp(1 - deltaRatio * 0.12, 0.82, 1.18);
    if (Math.abs(adjust - 1) < 0.03) continue;
    out[key] = Number(adjust.toFixed(3));
  }
  return out;
}

function buildBossOverrides(skillDiffGlobal) {
  const triggerMap = {
    smash_stun: "combat_loop",
    mountain_jump_stun: "aggro_changed_and_far",
    locust_swarm: "ultimate_cycle",
    spirit_wave: "combat_loop",
    bear_smash_stun: "combat_loop"
  };
  const agg = {};
  for (const row of skillDiffGlobal || []) {
    const skill = String(row.key || "");
    const trigger = triggerMap[skill];
    if (!trigger) continue;
    const node = Number(row.node || 0);
    const godot = Number(row.godot || 0);
    const deltaRatio = (godot - node) / Math.max(1, node);
    const adjust = clamp(1 + deltaRatio * 0.08, 0.85, 1.2);
    if (!agg[trigger]) agg[trigger] = [];
    agg[trigger].push(adjust);
  }
  const out = {};
  for (const [trigger, arr] of Object.entries(agg)) {
    const avg = arr.reduce((a, b) => a + b, 0) / arr.length;
    if (Math.abs(avg - 1) < 0.03) continue;
    out[trigger] = Number(avg.toFixed(3));
  }
  return out;
}

function buildScalar(rows) {
  let nodeWin = 0;
  let godotWin = 0;
  let compared = 0;
  for (const r of rows || []) {
    compared += 1;
    if (String(r.nodeResult || "") === "win") nodeWin += 1;
    if (String(r.godotResult || "") === "win") godotWin += 1;
  }
  if (compared === 0) {
    return { heroOutgoingMul: 1.0, bossIncomingMul: 1.0 };
  }
  const nodeRate = nodeWin / compared;
  const godotRate = godotWin / compared;
  const diff = godotRate - nodeRate;
  return {
    heroOutgoingMul: Number(clamp(1 - diff * 0.18, 0.88, 1.12).toFixed(3)),
    bossIncomingMul: Number(clamp(1 + diff * 0.15, 0.88, 1.12).toFixed(3))
  };
}

function main() {
  const comparePath = pick(process.argv[2], "battle_replay_compare_godot_v1.json");
  if (!fs.existsSync(comparePath)) {
    console.error("COMPARE_NOT_FOUND", comparePath);
    process.exit(1);
  }
  const c = readJson(comparePath);
  const actionOverrides = buildActionOverrides(c.actionDiffGlobal || []);
  const bossOverrides = buildBossOverrides(c.bossSkillDiffGlobal || []);
  const scalar = buildScalar(c.rows || []);

  const overrides = {
    meta: {
      version: "1.0-godot-tuning-overrides-v1",
      generatedAt: "2026-03-10",
      sourceCompare: comparePath
    },
    heroActionMul: actionOverrides,
    bossTriggerMul: bossOverrides,
    scalar
  };

  const suggestions = {
    meta: {
      version: "1.0-godot-tuning-suggestions-v1",
      generatedAt: "2026-03-10",
      sourceCompare: comparePath
    },
    summary: {
      comparedWaves: Number(c?.meta?.comparedWaves || 0),
      sameResultRate: Number(c?.meta?.sameResultRate || 0),
      actionOverrideCount: Object.keys(actionOverrides).length,
      bossOverrideCount: Object.keys(bossOverrides).length
    },
    actionDiffGlobal: c.actionDiffGlobal || [],
    bossSkillDiffGlobal: c.bossSkillDiffGlobal || [],
    recommendedOverrides: overrides
  };

  fs.writeFileSync("godot_tuning_overrides_v1.json", JSON.stringify(overrides, null, 2), "utf8");
  fs.writeFileSync("godot_tuning_suggestions_v1.json", JSON.stringify(suggestions, null, 2), "utf8");
  console.log("godot_tuning_overrides_v1.json generated");
  console.log("godot_tuning_suggestions_v1.json generated");
  console.log("TUNING_SUMMARY", suggestions.summary);
}

main();
