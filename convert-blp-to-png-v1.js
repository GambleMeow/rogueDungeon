const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");
const { decodeBLP, getBLPImageData } = require("war3-model");

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function convertOne(srcPath, outDir) {
  const src = fs.readFileSync(srcPath);
  const decoded = decodeBLP(toArrayBuffer(src));
  const img = getBLPImageData(decoded, 0);
  const png = new PNG({ width: img.width, height: img.height });
  png.data.set(Buffer.from(img.data));

  const outName = path.basename(srcPath).replace(/\.blp$/i, ".png");
  const outPath = path.join(outDir, outName);
  fs.writeFileSync(outPath, PNG.sync.write(png));

  return { outPath, width: img.width, height: img.height };
}

function main() {
  const sourceDirs = ["boss-hero-model-deps", "unit-models-from-refs"];
  const outRoot = "godot-assets";
  const texOutDir = path.join(outRoot, "textures");
  ensureDir(texOutDir);

  const rows = [];
  for (const dir of sourceDirs) {
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir);
    for (const f of files) {
      if (!/\.blp$/i.test(f)) continue;
      const srcPath = path.join(dir, f);
      try {
        const r = convertOne(srcPath, texOutDir);
        rows.push({
          sourceDir: dir,
          sourcePath: srcPath.replace(/\\/g, "/"),
          pngPath: r.outPath.replace(/\\/g, "/"),
          width: r.width,
          height: r.height,
          ok: true
        });
      } catch (e) {
        rows.push({
          sourceDir: dir,
          sourcePath: srcPath.replace(/\\/g, "/"),
          ok: false,
          reason: String(e && e.message ? e.message : e)
        });
      }
    }
  }

  const out = {
    meta: {
      version: "1.0-blp-to-png-v1",
      generatedAt: "2026-03-10",
      total: rows.length,
      okCount: rows.filter((x) => x.ok).length,
      failedCount: rows.filter((x) => !x.ok).length
    },
    rows
  };
  fs.writeFileSync("godot_texture_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_texture_manifest_v1.json generated");
  console.log("TEXTURE_CONVERT_SUMMARY", out.meta);
}

main();
