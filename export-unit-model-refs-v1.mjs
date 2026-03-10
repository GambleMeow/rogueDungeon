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
  const refReport = JSON.parse(fs.readFileSync("unit_model_refs_report_v1.json", "utf8"));
  const refs = refReport.uniqueModelRefs || [];
  const outDir = path.resolve("unit-models-from-refs");
  fs.mkdirSync(outDir, { recursive: true });

  const map = new War3Map(toArrayBuffer(fs.readFileSync(mapPath)), true);
  const names = map.getFileNames() || [];
  const idx = new Map();
  for (const n of names) idx.set(normalizePath(n).toLowerCase(), n);

  const rows = [];
  for (const ref of refs) {
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
    const outPath = path.join(outDir, sanitizeFileName(archiveName));
    fs.writeFileSync(outPath, Buffer.from(new Uint8Array(ab)));
    rows.push({ ref, archiveName, ok: true, outPath: outPath.replace(/\\/g, "/"), size: ab.byteLength });
  }

  const okCount = rows.filter((x) => x.ok).length;
  const out = {
    meta: {
      version: "1.0-unit-model-export-v1",
      generatedAt: "2026-03-10",
      refCount: refs.length,
      exported: okCount,
      failed: rows.length - okCount
    },
    rows
  };
  fs.writeFileSync("unit_model_export_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("unit_model_export_manifest_v1.json generated");
  console.log("UNIT_MODEL_EXPORT_SUMMARY", out.meta);
}

main();
