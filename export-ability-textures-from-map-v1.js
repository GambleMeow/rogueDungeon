const fs = require("fs");
const path = require("path");
const { decodeBLP, getBLPImageData } = require("war3-model");
const { PNG } = require("pngjs");

async function loadWar3Map() {
  const mod = await import("w3x-parser");
  const War3Map = mod.default;
  const mapPath = "map-archive-extract/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x";
  const b = fs.readFileSync(mapPath);
  const ab = b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
  return new War3Map(ab, true);
}

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function normalizePath(s) {
  return String(s || "").replace(/\0/g, "").replace(/\//g, "\\").trim();
}

function sanitizeForFile(p) {
  return normalizePath(p).replace(/[\\/:*?"<>|]/g, "_").replace(/\.blp$/i, ".png");
}

function decodeBlpToPngBuffer(blpAb) {
  const decoded = decodeBLP(blpAb);
  const img = getBLPImageData(decoded, 0);
  const png = new PNG({ width: img.width, height: img.height });
  png.data.set(Buffer.from(img.data));
  return { width: img.width, height: img.height, buf: PNG.sync.write(png) };
}

function collectNeededPaths(bindings) {
  const need = new Set();
  for (const a of bindings.abilityEffectBindings || []) {
    const icon = String(a.iconPath || "");
    if (/\.blp$/i.test(icon)) need.add(normalizePath(icon));
    for (const r of a.resourcePaths || []) {
      const p = String(r.path || "");
      if (/\.blp$/i.test(p)) need.add(normalizePath(p));
    }
  }
  return [...need];
}

function pickArchiveName(ref, indexMap) {
  const n = normalizePath(ref);
  const cands = [n, n.toLowerCase(), `war3mapImported\\${n}`, `war3mapImported\\${n}`.toLowerCase()];
  for (const c of cands) {
    const hit = indexMap.get(c.toLowerCase());
    if (hit) return hit;
  }
  return null;
}

async function main() {
  const bindings = JSON.parse(fs.readFileSync("godot_entity_bindings_v2.json", "utf8"));
  const outDir = "godot-assets/textures";
  fs.mkdirSync(outDir, { recursive: true });

  const map = await loadWar3Map();
  const names = map.getFileNames() || [];
  const idx = new Map();
  for (const n of names) idx.set(normalizePath(n).toLowerCase(), n);

  const need = collectNeededPaths(bindings);
  const rows = [];
  for (const ref of need) {
    const archiveName = pickArchiveName(ref, idx);
    if (!archiveName) {
      rows.push({ ref, ok: false, reason: "not found in map archive" });
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
    try {
      const { width, height, buf } = decodeBlpToPngBuffer(ab);
      const outPath = path.join(outDir, sanitizeForFile(ref));
      fs.writeFileSync(outPath, buf);
      rows.push({
        ref,
        archiveName,
        ok: true,
        pngPath: outPath.replace(/\\/g, "/"),
        width,
        height
      });
    } catch (e) {
      rows.push({ ref, archiveName, ok: false, reason: String(e && e.message ? e.message : e) });
    }
  }

  const out = {
    meta: {
      version: "1.0-export-ability-textures-from-map-v1",
      generatedAt: "2026-03-10",
      requested: need.length,
      exported: rows.filter((x) => x.ok).length,
      failed: rows.filter((x) => !x.ok).length
    },
    rows
  };
  fs.writeFileSync("ability_texture_export_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("ability_texture_export_manifest_v1.json generated");
  console.log("ABILITY_TEXTURE_EXPORT_STATS", out.meta);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
