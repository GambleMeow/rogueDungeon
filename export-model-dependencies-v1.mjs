import fs from "fs";
import path from "path";
import War3Map from "w3x-parser";

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function normalizePath(s) {
  return String(s || "").replace(/\0/g, "").replace(/\//g, "\\").trim();
}

function sanitizeFileName(s) {
  return s.replace(/[\\/:*?"<>|]/g, "_");
}

function extractRefsFromBinary(buf) {
  const text = buf.toString("latin1");
  const re = /[A-Za-z0-9_\\/\- .]+\.(?:blp|mdx|mdl|dds|tga)/gi;
  const out = new Set();
  let m;
  while ((m = re.exec(text))) out.add(normalizePath(m[0]));
  return [...out];
}

function pickArchiveName(ref, mapIndex) {
  const n = normalizePath(ref);
  const cands = [
    n,
    n.toLowerCase(),
    `war3mapImported\\${n}`,
    `war3mapImported\\${n}`.toLowerCase()
  ];
  for (const c of cands) {
    const hit = mapIndex.get(c.toLowerCase());
    if (hit) return hit;
  }
  return null;
}

function main() {
  const mapPath = path.resolve("map-archive-extract/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x");
  const modelDir = path.resolve("boss-hero-models");
  const outDir = path.resolve("boss-hero-model-deps");
  fs.mkdirSync(outDir, { recursive: true });

  const modelFiles = fs
    .readdirSync(modelDir)
    .filter((f) => /\.(mdx|mdl)$/i.test(f))
    .map((f) => path.join(modelDir, f));

  const refs = new Set();
  for (const file of modelFiles) {
    const b = fs.readFileSync(file);
    for (const r of extractRefsFromBinary(b)) refs.add(r);
  }

  const map = new War3Map(toArrayBuffer(fs.readFileSync(mapPath)), true);
  const names = map.getFileNames() || [];
  const idx = new Map();
  for (const n of names) idx.set(normalizePath(n).toLowerCase(), n);

  const rows = [];
  for (const ref of [...refs].sort()) {
    const archiveName = pickArchiveName(ref, idx);
    if (!archiveName) {
      rows.push({ ref, ok: false, reason: "not found in archive" });
      continue;
    }
    const f = map.get(archiveName);
    if (!f) {
      rows.push({ ref, archiveName, ok: false, reason: "archive get failed" });
      continue;
    }
    const ab = f.arrayBuffer();
    if (!ab) {
      rows.push({ ref, archiveName, ok: false, reason: "decode failed" });
      continue;
    }
    const outName = sanitizeFileName(archiveName);
    const outPath = path.join(outDir, outName);
    fs.writeFileSync(outPath, Buffer.from(new Uint8Array(ab)));
    rows.push({ ref, archiveName, ok: true, outPath: outPath.replace(/\\/g, "/"), size: ab.byteLength });
  }

  const okCount = rows.filter((x) => x.ok).length;
  const out = {
    meta: {
      version: "1.0-model-deps-export-v1",
      generatedAt: "2026-03-10",
      sourceModelCount: modelFiles.length,
      dependencyRefCount: refs.size,
      exported: okCount,
      failed: rows.length - okCount
    },
    rows
  };
  fs.writeFileSync("boss_hero_model_deps_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("boss_hero_model_deps_manifest_v1.json generated");
  console.log("MODEL_DEPS_EXPORT_SUMMARY", out.meta);
}

main();
