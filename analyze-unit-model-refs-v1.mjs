import fs from "fs";
import path from "path";
import War3Map from "w3x-parser";

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function normalize(s) {
  return String(s || "").replace(/\0/g, "").replace(/\//g, "\\").trim();
}

function walk(node, fn, p = []) {
  if (node === null || node === undefined) return;
  fn(node, p);
  if (Array.isArray(node)) {
    for (let i = 0; i < node.length; i++) walk(node[i], fn, [...p, String(i)]);
    return;
  }
  if (typeof node === "object") {
    for (const [k, v] of Object.entries(node)) walk(v, fn, [...p, k]);
  }
}

function main() {
  const mapPath = path.resolve("map-archive-extract/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x");
  const map = new War3Map(toArrayBuffer(fs.readFileSync(mapPath)), true);
  const mods = map.readModifications() || {};

  const rows = [];
  for (const [modType, modObj] of Object.entries(mods)) {
    walk(modObj, (n, stack) => {
      if (typeof n !== "string") return;
      const v = normalize(n);
      if (!/\.(mdx|mdl)$/i.test(v)) return;
      rows.push({
        modType,
        path: stack.join("."),
        modelPath: v
      });
    });
  }

  const unique = [...new Set(rows.map((r) => r.modelPath))].sort();
  const out = {
    meta: {
      version: "1.0-unit-model-refs-v1",
      generatedAt: "2026-03-10",
      mapPath: mapPath.replace(/\\/g, "/")
    },
    stats: {
      rawRefs: rows.length,
      uniqueModelRefs: unique.length
    },
    uniqueModelRefs: unique,
    refs: rows.slice(0, 5000)
  };
  fs.writeFileSync("unit_model_refs_report_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("unit_model_refs_report_v1.json generated");
  console.log("UNIT_MODEL_REFS_STATS", out.stats);
}

main();
