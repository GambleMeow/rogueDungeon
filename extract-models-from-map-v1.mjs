import fs from "fs";
import path from "path";
import War3Map from "w3x-parser";

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function normalizeModelPath(s) {
  return String(s).replace(/\0/g, "").trim();
}

function hasModelExt(s) {
  return /\.(mdx|mdl|blp|dds|tga)$/i.test(s);
}

function extractModelLikeFromText(text) {
  if (!text) return [];
  const out = new Set();
  const re = /[A-Za-z0-9_\\/\- .]+\.(?:mdx|mdl|blp|dds|tga)/gi;
  let m;
  while ((m = re.exec(text))) out.add(normalizeModelPath(m[0]));
  return [...out];
}

function walk(obj, visitor, pathStack = []) {
  if (obj === null || obj === undefined) return;
  visitor(obj, pathStack);
  if (Array.isArray(obj)) {
    for (let i = 0; i < obj.length; i++) walk(obj[i], visitor, [...pathStack, String(i)]);
    return;
  }
  if (typeof obj === "object") {
    for (const [k, v] of Object.entries(obj)) walk(v, visitor, [...pathStack, k]);
  }
}

function main() {
  const mapPath = path.resolve("map-archive-extract/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x");
  const mapBuf = fs.readFileSync(mapPath);
  const map = new War3Map(toArrayBuffer(mapBuf), true);

  const archiveNames = map.getFileNames() || [];
  const importNames = map.getImportNames() || [];
  const scriptText = map.getScript() || "";
  const mods = map.readModifications() || {};

  const archiveModelFiles = archiveNames.filter(hasModelExt).map(normalizeModelPath);
  const importModelFiles = importNames.filter(hasModelExt).map(normalizeModelPath);
  const scriptModelRefs = extractModelLikeFromText(scriptText);

  const modificationModelRefs = [];
  for (const [modType, modObj] of Object.entries(mods)) {
    walk(modObj, (node, stack) => {
      if (typeof node === "string" && hasModelExt(node)) {
        modificationModelRefs.push({
          modType,
          path: stack.join("."),
          value: normalizeModelPath(node)
        });
      }
    });
  }

  const merged = new Set([
    ...archiveModelFiles,
    ...importModelFiles,
    ...scriptModelRefs,
    ...modificationModelRefs.map((x) => x.value)
  ]);

  const out = {
    meta: {
      version: "1.0-map-model-extract-v1",
      generatedAt: "2026-03-10",
      mapPath: mapPath.replace(/\\/g, "/")
    },
    stats: {
      archiveFileCount: archiveNames.length,
      importCount: importNames.length,
      archiveModelCount: archiveModelFiles.length,
      importModelCount: importModelFiles.length,
      scriptModelRefCount: scriptModelRefs.length,
      modificationModelRefCount: modificationModelRefs.length,
      uniqueModelLikeCount: merged.size
    },
    archiveModelFiles,
    importModelFiles,
    scriptModelRefs,
    modificationModelRefs: modificationModelRefs.slice(0, 500),
    uniqueModelLikePaths: [...merged].sort()
  };

  fs.writeFileSync("map_model_assets_report_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("map_model_assets_report_v1.json generated");
  console.log("MODEL_REPORT_STATS", out.stats);
}

main();
