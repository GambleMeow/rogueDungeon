const fs = require("fs");
const path = require("path");
const unrar = require("node-unrar-js");

async function main() {
  const rarPath = path.resolve("3DMGAME-KKrgdlV29982.rar");
  const outDir = path.resolve("map-archive-extract");
  fs.mkdirSync(outDir, { recursive: true });

  const extractor = await unrar.createExtractorFromFile({
    filepath: rarPath,
    targetPath: outDir
  });

  const list = extractor.getFileList();
  const headers = Array.from(list.fileHeaders || []);
  const files = headers.map((h) => h.name);
  fs.writeFileSync("map_archive_filelist_v1.json", JSON.stringify({ count: files.length, files }, null, 2), "utf8");
  console.log("map_archive_filelist_v1.json generated", files.length);

  const target = files.find((f) => /\.w3x$/i.test(f) || /\.w3m$/i.test(f));
  if (!target) {
    console.log("no w3x/w3m in archive");
    return;
  }
  console.log("map file in rar:", target);

  const extracted = extractor.extract({ files: [target] });
  const resultFiles = Array.from(extracted.files || []);
  const first = resultFiles[0];
  if (!first || !first.extraction) {
    console.error("extract failed or no output");
    process.exit(1);
  }
  const outPath = path.resolve(target);
  fs.writeFileSync(outPath, first.extraction);
  console.log("map extracted:", outPath, first.extraction.length);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
