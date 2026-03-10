const fs = require("fs");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function scoreName(name) {
  const n = String(name || "").toLowerCase();
  let score = 0;
  let cls = "unknown";
  if (n.includes("boss")) {
    score += 5;
    cls = "boss";
  }
  if (n.includes("hero")) {
    score += 5;
    cls = cls === "boss" ? "boss_or_hero" : "hero";
  }
  if (/(demonhunter|warden|death_knight|tyrael|invoker|spider)/i.test(n)) score += 3;
  if (/(portrait|warning|jinggao)/i.test(n)) score -= 2;
  return { score, cls };
}

function main() {
  const a = readJson("boss_hero_model_manifest_v1.json");
  const b = readJson("unit_model_export_manifest_v1.json");

  const merged = new Map();
  for (const r of a.files || []) {
    if (!r.ok) continue;
    merged.set(String(r.name).toLowerCase(), {
      name: r.name,
      outPath: r.outPath,
      size: r.size || 0,
      source: ["keyword_export_v1"]
    });
  }
  for (const r of b.rows || []) {
    if (!r.ok) continue;
    const key = String(r.archiveName || r.ref || "").toLowerCase();
    if (!merged.has(key)) {
      merged.set(key, {
        name: r.archiveName || r.ref,
        outPath: r.outPath,
        size: r.size || 0,
        source: ["unit_ref_export_v1"]
      });
    } else {
      const x = merged.get(key);
      if (!x.source.includes("unit_ref_export_v1")) x.source.push("unit_ref_export_v1");
    }
  }

  const rows = [];
  for (const x of merged.values()) {
    const { score, cls } = scoreName(x.name);
    rows.push({
      ...x,
      guessClass: cls,
      guessScore: score
    });
  }
  rows.sort((m, n) => n.guessScore - m.guessScore || n.size - m.size);

  const out = {
    meta: {
      version: "1.0-boss-hero-model-candidates-v2",
      generatedAt: "2026-03-10",
      totalExportedModels: rows.length
    },
    stats: {
      heroLike: rows.filter((x) => x.guessClass === "hero").length,
      bossLike: rows.filter((x) => x.guessClass === "boss").length,
      mixedLike: rows.filter((x) => x.guessClass === "boss_or_hero").length,
      highConfidence: rows.filter((x) => x.guessScore >= 6).length
    },
    candidates: rows
  };

  fs.writeFileSync("boss_hero_model_candidates_v2.json", JSON.stringify(out, null, 2), "utf8");
  console.log("boss_hero_model_candidates_v2.json generated");
  console.log("MODEL_CANDIDATE_STATS", out.stats);
}

main();
