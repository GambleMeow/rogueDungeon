const fs = require("fs");
const path = require("path");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function copyIfExists(src, dst) {
  if (!fs.existsSync(src)) return false;
  ensureDir(path.dirname(dst));
  fs.copyFileSync(src, dst);
  return true;
}

function main() {
  const curated = readJson("boss_hero_model_curated_manifest_v1.json");
  const candidates = readJson("boss_hero_model_candidates_v2.json");
  const deps = readJson("boss_hero_model_deps_manifest_v1.json");
  const textures = readJson("godot_texture_manifest_v1.json");

  const outRoot = "godot-assets";
  const modelOut = path.join(outRoot, "models_war3");
  const textureOut = path.join(outRoot, "textures");
  ensureDir(modelOut);
  ensureDir(textureOut);
  const oldModels = fs.existsSync(modelOut) ? fs.readdirSync(modelOut) : [];
  for (const f of oldModels) {
    if (/\.(mdx|mdl)$/i.test(f)) {
      fs.unlinkSync(path.join(modelOut, f));
    }
  }

  const curatedMeta = new Map((curated.models || []).map((m) => [String(m.name || "").toLowerCase(), m]));
  const modelRows = [];
  const selectedByName = new Map();
  for (const c of candidates.candidates || []) {
    const src = String(c.outPath || "");
    const file = path.basename(src);
    if (!/\.(mdx|mdl)$/i.test(file)) continue;
    if (!selectedByName.has(file.toLowerCase())) selectedByName.set(file.toLowerCase(), { src, file });
  }
  for (const picked of selectedByName.values()) {
    const src = picked.src;
    const f = picked.file;
    const dst = path.join(modelOut, f);
    const ok = copyIfExists(src, dst);
    const meta = curatedMeta.get(f.toLowerCase());
    modelRows.push({
      name: f,
      guessClass: meta?.guessClass || "unknown",
      guessScore: Number(meta?.guessScore || 0),
      sourcePath: src.replace(/\\/g, "/"),
      packedPath: dst.replace(/\\/g, "/"),
      ok
    });
  }

  const depRows = [];
  for (const d of deps.rows || []) {
    if (!d.ok) continue;
    const src = d.outPath;
    const file = path.basename(src);
    const dst = path.join(modelOut, file);
    const ok = copyIfExists(src, dst);
    depRows.push({
      ref: d.ref,
      archiveName: d.archiveName,
      sourcePath: src.replace(/\\/g, "/"),
      packedPath: dst.replace(/\\/g, "/"),
      ok
    });
  }

  const texRows = [];
  for (const t of textures.rows || []) {
    if (!t.ok) continue;
    const src = t.pngPath;
    const file = path.basename(src);
    const dst = path.join(textureOut, file);
    const ok = copyIfExists(src, dst);
    texRows.push({
      sourcePath: src.replace(/\\/g, "/"),
      packedPath: dst.replace(/\\/g, "/"),
      ok
    });
  }

  const out = {
    meta: {
      version: "1.0-godot-model-pack-v1",
      generatedAt: "2026-03-10"
    },
    stats: {
      sourcePoolModels: modelRows.length,
      sourceCandidateModels: selectedByName.size,
      curatedModels: (curated.models || []).length,
      modelDeps: depRows.length,
      textures: texRows.length
    },
    models: modelRows,
    modelDependencies: depRows,
    textures: texRows,
    note: "models_war3 contains MDX/MDL sources; textures are converted PNG for Godot materials."
  };

  fs.writeFileSync("godot_model_pack_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_model_pack_manifest_v1.json generated");
  console.log("GODOT_MODEL_PACK_STATS", out.stats);
}

main();
