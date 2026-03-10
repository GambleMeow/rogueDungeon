const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function makeCommonPoints(shape) {
  if (shape === "circle") {
    return {
      heroSpawnPoints: [
        { id: "h1", x: 20, y: 50 },
        { id: "h2", x: 24, y: 40 },
        { id: "h3", x: 24, y: 60 },
        { id: "h4", x: 30, y: 50 }
      ],
      bossSpawnPoint: { x: 78, y: 50 },
      objectivePoint: { x: 50, y: 50 }
    };
  }
  if (shape === "rectangle") {
    return {
      heroSpawnPoints: [
        { id: "h1", x: 15, y: 30 },
        { id: "h2", x: 15, y: 45 },
        { id: "h3", x: 15, y: 60 },
        { id: "h4", x: 15, y: 75 }
      ],
      bossSpawnPoint: { x: 85, y: 50 },
      objectivePoint: { x: 50, y: 50 }
    };
  }
  if (shape === "ring") {
    return {
      heroSpawnPoints: [
        { id: "h1", x: 18, y: 50 },
        { id: "h2", x: 26, y: 36 },
        { id: "h3", x: 26, y: 64 },
        { id: "h4", x: 36, y: 50 }
      ],
      bossSpawnPoint: { x: 70, y: 50 },
      objectivePoint: { x: 50, y: 50 }
    };
  }
  return {
    heroSpawnPoints: [
      { id: "h1", x: 18, y: 50 },
      { id: "h2", x: 22, y: 40 },
      { id: "h3", x: 22, y: 60 },
      { id: "h4", x: 28, y: 50 }
    ],
    bossSpawnPoint: { x: 75, y: 50 },
    objectivePoint: { x: 50, y: 50 }
  };
}

function makeHazards(terrainId) {
  if (terrainId === "arena_line_skill") {
    return [
      { id: "hz_line_1", type: "line_lane", x1: 35, y1: 20, x2: 90, y2: 20 },
      { id: "hz_line_2", type: "line_lane", x1: 35, y1: 50, x2: 90, y2: 50 },
      { id: "hz_line_3", type: "line_lane", x1: 35, y1: 80, x2: 90, y2: 80 }
    ];
  }
  if (terrainId === "arena_fan_facing") {
    return [{ id: "hz_fan_front", type: "frontal_fan_zone", cx: 70, cy: 50, radius: 28, angleDeg: 70 }];
  }
  if (terrainId === "arena_circle_warning") {
    return [
      { id: "hz_ring_1", type: "circle_warning", cx: 60, cy: 45, r: 12 },
      { id: "hz_ring_2", type: "circle_warning", cx: 74, cy: 62, r: 10 }
    ];
  }
  if (terrainId === "arena_random_reposition") {
    return [{ id: "hz_blink_pressure", type: "reposition_hotspots", points: [{ x: 62, y: 30 }, { x: 80, y: 50 }, { x: 62, y: 70 }] }];
  }
  if (terrainId === "arena_edge_risky") {
    return [{ id: "hz_edge_pinch", type: "edge_risk", edge: "right" }];
  }
  return [];
}

function makeBlockers(terrainId) {
  if (terrainId === "arena_random_reposition") {
    return [
      { id: "blk_1", x: 48, y: 50, w: 6, h: 24 },
      { id: "blk_2", x: 66, y: 36, w: 6, h: 14 },
      { id: "blk_3", x: 66, y: 64, w: 6, h: 14 }
    ];
  }
  if (terrainId === "arena_edge_risky") {
    return [
      { id: "blk_1", x: 84, y: 20, w: 8, h: 16 },
      { id: "blk_2", x: 84, y: 64, w: 8, h: 16 }
    ];
  }
  if (terrainId === "arena_stack_spread_switch") {
    return [{ id: "blk_center", x: 52, y: 50, w: 5, h: 5 }];
  }
  return [];
}

function makeSafeZones(terrainId) {
  if (terrainId === "arena_outer_ring") {
    return [{ id: "safe_outer", type: "ring_lane", cx: 50, cy: 50, rMin: 28, rMax: 40 }];
  }
  if (terrainId === "arena_open") {
    return [{ id: "safe_kite", type: "open_band", xMin: 25, xMax: 55, yMin: 25, yMax: 75 }];
  }
  if (terrainId === "arena_circle_warning") {
    return [{ id: "safe_gap", type: "gap_between_rings", xMin: 40, xMax: 55, yMin: 30, yMax: 70 }];
  }
  return [];
}

function main() {
  const terrain = readJson("terrain_schema_v1.json");
  const templates = terrain.templates || [];

  const instances = templates.map((t) => {
    const shape = t.geometry?.shape || "irregular";
    const common = makeCommonPoints(shape);
    return {
      terrainId: t.terrainId,
      name: t.name,
      tags: t.tags || [],
      geometry: t.geometry || {},
      heroSpawnPoints: common.heroSpawnPoints,
      bossSpawnPoint: common.bossSpawnPoint,
      objectivePoint: common.objectivePoint,
      blockers: makeBlockers(t.terrainId),
      warningZones: makeHazards(t.terrainId),
      safeZones: makeSafeZones(t.terrainId),
      navHints: {
        preferredLanes: t.geometry?.lanes || "none",
        avoidEdge: (t.tags || []).includes("edge_hugging"),
        spreadRecommended: (t.tags || []).includes("spread_requirement"),
        stackRecommended: (t.tags || []).includes("stack_requirement")
      }
    };
  });

  const out = {
    meta: {
      version: "1.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      source: "terrain_schema_v1.json"
    },
    instanceCount: instances.length,
    terrainInstances: instances
  };

  fs.writeFileSync("terrain_instances_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("terrain_instances_v1.json generated");
}

main();
