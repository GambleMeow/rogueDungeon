const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function uniq(arr) {
  return [...new Set(arr)];
}

function makeRulesForTemplate(t) {
  const id = t.terrainId;
  const tags = t.tags || [];

  const rule = {
    terrainId: id,
    tags,
    actionPriorityDelta: {},
    actionDenyList: [],
    actionRequireTag: {},
    notes: []
  };

  if (id === "arena_open") {
    rule.actionPriorityDelta = {
      primary_pattern: 8,
      burst_or_execute: 6,
      mobility_reposition: -4
    };
    rule.notes.push("开阔地鼓励正面输出，弱化频繁位移。");
  }

  if (id === "arena_outer_ring") {
    rule.actionPriorityDelta = {
      mobility_reposition: 16,
      primary_pattern: 5,
      control_cast: -4
    };
    rule.notes.push("外圈风筝，位移收益高。");
  }

  if (id === "arena_edge_risky") {
    rule.actionPriorityDelta = {
      defensive_window: 12,
      mobility_reposition: 10,
      burst_or_execute: -8
    };
    rule.notes.push("边缘高风险，优先生存与重定位。");
  }

  if (id === "arena_line_skill") {
    rule.actionPriorityDelta = {
      mobility_reposition: 14,
      control_cast: 6,
      summon_maintenance: -10
    };
    rule.actionDenyList = ["summon_maintenance"];
    rule.notes.push("直线压制地形减少召唤驻场价值。");
  }

  if (id === "arena_fan_facing") {
    rule.actionPriorityDelta = {
      mobility_reposition: 12,
      control_cast: 8,
      primary_pattern: -5
    };
    rule.notes.push("扇形朝向地形强调换位和控场。");
  }

  if (id === "arena_circle_warning") {
    rule.actionPriorityDelta = {
      defensive_window: 14,
      mobility_reposition: 10,
      summon_maintenance: -8
    };
    rule.actionRequireTag = {
      summon_maintenance: "stack_requirement"
    };
    rule.notes.push("圈型预警地形抑制扎堆召唤。");
  }

  if (id === "arena_random_reposition") {
    rule.actionPriorityDelta = {
      mobility_reposition: 20,
      control_cast: 5,
      burst_or_execute: -10,
      summon_maintenance: -12
    };
    rule.actionDenyList = ["burst_or_execute"];
    rule.notes.push("随机位移地形打断爆发节奏。");
  }

  if (id === "arena_stack_spread_switch") {
    rule.actionPriorityDelta = {
      control_cast: 10,
      defensive_window: 8,
      summon_maintenance: 4
    };
    rule.notes.push("集合/分散切换，控场和团队生存优先。");
  }

  // tag-level fallback rule
  if (tags.includes("spread_requirement")) {
    rule.actionPriorityDelta.summon_maintenance =
      (rule.actionPriorityDelta.summon_maintenance || 0) - 6;
  }
  if (tags.includes("stack_requirement")) {
    rule.actionPriorityDelta.summon_maintenance =
      (rule.actionPriorityDelta.summon_maintenance || 0) + 6;
  }

  rule.actionDenyList = uniq(rule.actionDenyList);
  return rule;
}

function main() {
  const terrain = readJson("terrain_schema_v1.json");
  const templates = terrain.templates || [];
  const rules = templates.map(makeRulesForTemplate);

  const out = {
    meta: {
      version: "1.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      source: "terrain_schema_v1.json"
    },
    ruleCount: rules.length,
    rules
  };

  fs.writeFileSync("terrain_action_rules_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("terrain_action_rules_v1.json generated");
}

main();
