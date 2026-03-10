const fs = require("fs");
const path = require("path");
const { parseMDX, parseMDL } = require("war3-model");

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function main() {
  const inDir = "godot-assets/models_war3";
  const outDir = "godot-assets/models_json";
  fs.mkdirSync(outDir, { recursive: true });
  const oldOut = fs.existsSync(outDir) ? fs.readdirSync(outDir) : [];
  for (const f of oldOut) {
    if (/\.json$/i.test(f)) {
      fs.unlinkSync(path.join(outDir, f));
    }
  }

  const rows = [];
  const files = fs.existsSync(inDir) ? fs.readdirSync(inDir) : [];
  for (const f of files) {
    const ext = path.extname(f).toLowerCase();
    if (ext !== ".mdx" && ext !== ".mdl") continue;
    const srcPath = path.join(inDir, f);
    try {
      const raw = fs.readFileSync(srcPath);
      const model = ext === ".mdx" ? parseMDX(toArrayBuffer(raw)) : parseMDL(raw.toString("utf8"));
      const base = path.basename(f, ext);
      const extTag = ext === ".mdx" ? "_mdx" : "_mdl";
      const outPath = path.join(outDir, `${base}${extTag}.json`);
      fs.writeFileSync(outPath, JSON.stringify(model, null, 2), "utf8");
      rows.push({
        sourcePath: srcPath.replace(/\\/g, "/"),
        sourceName: f,
        jsonPath: outPath.replace(/\\/g, "/"),
        ok: true
      });
    } catch (e) {
      rows.push({
        sourcePath: srcPath.replace(/\\/g, "/"),
        ok: false,
        reason: String(e && e.message ? e.message : e)
      });
    }
  }

  const out = {
    meta: {
      version: "1.0-war3-model-json-v1",
      generatedAt: "2026-03-10",
      total: rows.length,
      okCount: rows.filter((x) => x.ok).length,
      failedCount: rows.filter((x) => !x.ok).length
    },
    rows
  };
  fs.writeFileSync("godot_model_json_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_model_json_manifest_v1.json generated");
  console.log("MODEL_JSON_SUMMARY", out.meta);
}

main();
