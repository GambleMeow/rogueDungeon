const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function normalizePath(s) {
  return String(s || "").replace(/\0/g, "").replace(/\//g, "\\").trim();
}

function writePlaceholderPng(outPath) {
  const w = 64;
  const h = 64;
  const png = new PNG({ width: w, height: h });
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const idx = (y * w + x) * 4;
      const checker = ((x >> 3) + (y >> 3)) % 2 === 0;
      const c = checker ? 170 : 110;
      png.data[idx] = c;
      png.data[idx + 1] = 40;
      png.data[idx + 2] = 170;
      png.data[idx + 3] = 255;
    }
  }
  fs.writeFileSync(outPath, PNG.sync.write(png));
}

function main() {
  const health = readJson("godot_resource_health_v1.json");
  const exportManifest = readJson("ability_texture_export_manifest_v1.json");
  const mapAssets = readJson("map_model_assets_report_v1.json");

  const outDir = "godot-assets/textures";
  fs.mkdirSync(outDir, { recursive: true });
  const placeholder = path.join(outDir, "placeholder_ability.png");
  if (!fs.existsSync(placeholder)) writePlaceholderPng(placeholder);

  const archiveSet = new Set((mapAssets.uniqueModelLikePaths || []).map((x) => normalizePath(x).toLowerCase()));
  const failedByRef = new Map();
  for (const r of exportManifest.rows || []) {
    if (!r.ok) failedByRef.set(normalizePath(r.ref).toLowerCase(), r.reason || "unknown");
  }

  const fallbackRows = [];
  const summary = {
    totalIssues: (health.issues || []).length,
    withFallback: 0,
    missingInMap: 0,
    inMapButFailedDecode: 0,
    other: 0
  };

  for (const issue of health.issues || []) {
    const ref = normalizePath(issue.iconPath || issue.path || "").toLowerCase();
    if (!ref) continue;
    const inMap =
      archiveSet.has(ref) ||
      archiveSet.has(`war3mapimported\\${ref}`) ||
      archiveSet.has(ref.replace(/^war3mapimported\\/, ""));
    const failReason = failedByRef.get(ref) || failedByRef.get(`war3mapimported\\${ref}`) || "";

    let classification = "other";
    if (!inMap) classification = "missing_in_map";
    else if (failReason) classification = "in_map_but_decode_failed";

    if (classification === "missing_in_map") summary.missingInMap += 1;
    else if (classification === "in_map_but_decode_failed") summary.inMapButFailedDecode += 1;
    else summary.other += 1;

    fallbackRows.push({
      issueType: issue.type,
      abilityId: issue.id,
      sourcePath: issue.iconPath || issue.path || "",
      expectedPng: issue.expectedPng || "",
      classification,
      fallbackPng: placeholder.replace(/\\/g, "/")
    });
    summary.withFallback += 1;
  }

  const out = {
    meta: {
      version: "1.0-texture-fallbacks-v1",
      generatedAt: "2026-03-10"
    },
    summary,
    fallbackRows
  };
  fs.writeFileSync("godot_texture_fallback_map_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_texture_fallback_map_v1.json generated");
  console.log("TEXTURE_FALLBACK_SUMMARY", summary);
}

main();
