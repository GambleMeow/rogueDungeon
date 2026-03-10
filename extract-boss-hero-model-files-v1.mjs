import fs from "fs";
import path from "path";
import War3Map from "w3x-parser";

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function sanitizeName(name) {
  return name.replace(/[\\/:*?"<>|]/g, "_");
}

function hasModelExt(name) {
  return /\.(mdx|mdl)$/i.test(name);
}

function main() {
  const mapPath = path.resolve("map-archive-extract/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x");
  const outDir = path.resolve("boss-hero-models");
  fs.mkdirSync(outDir, { recursive: true });

  const map = new War3Map(toArrayBuffer(fs.readFileSync(mapPath)), true);
  const names = map.getFileNames() || [];
  const modelNames = names.filter(hasModelExt);
  const target = modelNames.filter((n) => /(hero|boss)/i.test(n));

  const rows = [];
  for (const name of target) {
    const f = map.get(name);
    if (!f) {
      rows.push({ name, ok: false, reason: "file not found in archive index" });
      continue;
    }
    const ab = f.arrayBuffer();
    if (!ab) {
      rows.push({ name, ok: false, reason: "decode failed" });
      continue;
    }
    const outName = sanitizeName(name);
    const outPath = path.join(outDir, outName);
    fs.writeFileSync(outPath, Buffer.from(new Uint8Array(ab)));
    rows.push({ name, ok: true, outPath: outPath.replace(/\\/g, "/"), size: ab.byteLength });
  }

  const okCount = rows.filter((x) => x.ok).length;
  const out = {
    meta: {
      version: "1.0-boss-hero-model-export-v1",
      generatedAt: "2026-03-10",
      mapPath: mapPath.replace(/\\/g, "/"),
      totalModelFilesInMap: modelNames.length,
      keywordMatched: target.length,
      exported: okCount,
      failed: rows.length - okCount
    },
    files: rows
  };
  fs.writeFileSync("boss_hero_model_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("boss_hero_model_manifest_v1.json generated");
  console.log("BOSS_HERO_MODEL_EXPORT_SUMMARY", out.meta);
}

main();
