const fs = require("fs");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function main() {
  const raw = readJson("godot_resource_health_v1.json");
  const fallback = readJson("godot_texture_fallback_map_v1.json");

  const fallbackSet = new Set(
    (fallback.fallbackRows || []).map((x) => `${x.issueType}|${x.abilityId}|${x.expectedPng || ""}|${x.sourcePath || ""}`)
  );

  const unresolved = [];
  let coveredByFallback = 0;
  for (const i of raw.issues || []) {
    const key = `${i.type}|${i.id}|${i.expectedPng || ""}|${i.iconPath || i.path || ""}`;
    if (fallbackSet.has(key)) coveredByFallback += 1;
    else unresolved.push(i);
  }

  const out = {
    meta: {
      version: "1.0-godot-resource-health-effective-v1",
      generatedAt: "2026-03-10"
    },
    stats: {
      rawIssueCount: (raw.issues || []).length,
      coveredByFallback,
      unresolvedCount: unresolved.length
    },
    unresolved
  };

  fs.writeFileSync("godot_resource_health_effective_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_resource_health_effective_v1.json generated");
  console.log("RESOURCE_HEALTH_EFFECTIVE_STATS", out.stats);
}

main();
