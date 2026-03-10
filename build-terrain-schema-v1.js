const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function countBy(list, key) {
  const m = {};
  for (const x of list) {
    const k = x[key] || "unknown";
    m[k] = (m[k] || 0) + 1;
  }
  return m;
}

function toBossNo(text) {
  const m = String(text || "").match(/(\d+)号BOSS/);
  return m ? Number(m[1]) : null;
}

function buildTemplates() {
  return [
    {
      terrainId: "arena_open",
      name: "开放圆形战场",
      tags: ["open_arena", "movement_check"],
      geometry: { shape: "circle", obstacles: "low", lanes: "none" },
      useCases: ["基础近战Boss", "全局走位教学"]
    },
    {
      terrainId: "arena_outer_ring",
      name: "外圈风筝战场",
      tags: ["outer_ring_pathing", "kite_and_pull"],
      geometry: { shape: "ring", obstacles: "low", lanes: "outer_ring" },
      useCases: ["绕外圈拉怪", "持续AOE规避"]
    },
    {
      terrainId: "arena_edge_risky",
      name: "边缘高风险战场",
      tags: ["edge_hugging", "corner_risk"],
      geometry: { shape: "irregular", obstacles: "medium", lanes: "edge_bias" },
      useCases: ["不贴边作战", "防边缘封位"]
    },
    {
      terrainId: "arena_line_skill",
      name: "直线技压制战场",
      tags: ["line_skill_lane", "movement_check"],
      geometry: { shape: "rectangle", obstacles: "low", lanes: "long_line" },
      useCases: ["直线冲锋/投射技能", "侧向规避"]
    },
    {
      terrainId: "arena_fan_facing",
      name: "扇形朝向战场",
      tags: ["fan_aoe_facing", "movement_check"],
      geometry: { shape: "semi_open", obstacles: "medium", lanes: "frontal_cone" },
      useCases: ["背后输出", "前方扇形规避"]
    },
    {
      terrainId: "arena_circle_warning",
      name: "圈型预警战场",
      tags: ["circle_aoe_zone", "spread_requirement"],
      geometry: { shape: "circle", obstacles: "medium", lanes: "multi_zone" },
      useCases: ["红圈分散", "圈间缝隙走位"]
    },
    {
      terrainId: "arena_random_reposition",
      name: "随机位移压力战场",
      tags: ["random_reposition_pressure", "anti_stuck_layout"],
      geometry: { shape: "irregular", obstacles: "medium", lanes: "dynamic" },
      useCases: ["Boss频繁换位", "防卡位重定位"]
    },
    {
      terrainId: "arena_stack_spread_switch",
      name: "集合/分散切换战场",
      tags: ["stack_requirement", "spread_requirement"],
      geometry: { shape: "open", obstacles: "low", lanes: "team_split_merge" },
      useCases: ["队伍集合吸收", "快速散开避伤"]
    }
  ];
}

function suggestPoolByWave(wave) {
  if (wave <= 5) return ["arena_open", "arena_line_skill", "arena_fan_facing"];
  if (wave <= 10) return ["arena_circle_warning", "arena_outer_ring", "arena_random_reposition"];
  if (wave <= 15) return ["arena_edge_risky", "arena_stack_spread_switch", "arena_random_reposition"];
  return ["arena_random_reposition", "arena_outer_ring", "arena_circle_warning", "arena_edge_risky"];
}

function main() {
  const cluesRaw = readJson("terrain_clues_raw_v1.json");
  const bossSchema = readJson("boss_wave_schema_v1.json");
  const clues = cluesRaw.terrainClues || [];
  const templates = buildTemplates();

  const bossClues = {};
  for (const c of clues) {
    const no = toBossNo(c.clueText);
    if (!no) continue;
    if (!bossClues[no]) bossClues[no] = [];
    bossClues[no].push({
      topicId: c.topicId,
      normalizedTag: c.normalizedTag,
      clueText: c.clueText
    });
  }

  const waves = (bossSchema.waves || []).map((w) => ({
    wave: w.wave,
    bossId: w.bossId,
    terrainPool: suggestPoolByWave(w.wave),
    selectionPolicy: "pick_by_boss_tag_then_rotate",
    confidence: "medium"
  }));

  const bossTerrainHints = [];
  for (let i = 1; i <= 21; i++) {
    const arr = bossClues[i] || [];
    const tagCounts = countBy(arr, "normalizedTag");
    const sortedTags = Object.entries(tagCounts)
      .sort((a, b) => b[1] - a[1])
      .map((x) => x[0]);
    bossTerrainHints.push({
      bossNo: i,
      dominantTags: sortedTags.slice(0, 3),
      clueCount: arr.length,
      sampleClues: arr.slice(0, 3)
    });
  }

  const out = {
    meta: {
      version: "1.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sources: ["terrain_clues_raw_v1.json", "boss_wave_schema_v1.json"],
      note: "Terrain templates inferred from strategy text clues."
    },
    stats: {
      clueCount: clues.length,
      tagDistribution: countBy(clues, "normalizedTag")
    },
    templates,
    bossTerrainHints,
    waves,
    implementationHints: {
      godot: [
        "Use TileMap layers: floor, obstacle, warning_zone.",
        "Each terrain template maps to a scene chunk with spawn points.",
        "At wave start choose terrain by dominant boss tags."
      ]
    }
  };

  fs.writeFileSync("terrain_schema_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("terrain_schema_v1.json generated");
}

main();
