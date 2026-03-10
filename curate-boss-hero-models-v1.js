const fs = require("fs");
const path = require("path");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function safeName(p) {
  return String(p).replace(/[\\/:*?"<>|]/g, "_");
}

function main() {
  const c = readJson("boss_hero_model_candidates_v2.json");
  const rows = c.candidates || [];
  const picked = rows.filter((x) => Number(x.guessScore || 0) >= 6);
  const outDir = "boss-hero-models-curated";
  fs.mkdirSync(outDir, { recursive: true });

  const outRows = [];
  for (const r of picked) {
    const src = String(r.outPath || "");
    if (!src || !fs.existsSync(src)) continue;
    const file = safeName(path.basename(src));
    const dst = path.join(outDir, file);
    fs.copyFileSync(src, dst);
    outRows.push({
      name: r.name,
      guessClass: r.guessClass,
      guessScore: r.guessScore,
      source: r.source,
      srcPath: src.replace(/\\/g, "/"),
      curatedPath: dst.replace(/\\/g, "/")
    });
  }

  const out = {
    meta: {
      version: "1.0-boss-hero-model-curated-v1",
      generatedAt: "2026-03-10",
      totalCandidates: rows.length,
      curatedCount: outRows.length
    },
    models: outRows
  };
  fs.writeFileSync("boss_hero_model_curated_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("boss_hero_model_curated_manifest_v1.json generated");
  console.log("CURATED_MODEL_SUMMARY", out.meta);
}

main();
