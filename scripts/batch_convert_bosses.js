const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { parseMDX } = require("war3-model");
const { NodeIO } = require("@gltf-transform/core");

const ROOT = "C:/Users/Administrator/Desktop/personal/rogueDungeon2";
const MAP_PATH = `${ROOT}/archive/map_source/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x`;
const MPQCLI = `${ROOT}/tools/mpqcli.exe`;
const CONVERTER = `${ROOT}/blender_convert.js`;
const OUT_ROOT = `${ROOT}/outputs/batch/boss`;

const BOSS_MODELS = [
  "NightmareSpiderBoss.mdx",
  "bossjinggaoh.mdx",
  "bossjinggaoh1.mdx",
  "bossjinggaoh2.mdx",
  "bossjinggaohzc.mdx",
  "hai_pa_de_lao_ban_sha_boss_of_fear.mdx",
  "boss_027.mdx",
];

function run(command, args, desc) {
  const r = spawnSync(command, args, {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.status !== 0) {
    throw new Error(
      `${desc}失败\nexit=${r.status}\nstdout=${r.stdout || ""}\nstderr=${r.stderr || ""}`
    );
  }
  return r.stdout || "";
}

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function listMpqFiles() {
  const out = run(MPQCLI, ["list", MAP_PATH], "读取MPQ文件列表");
  return out
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function extractFromMpq(fileInMpq, outDir) {
  run(MPQCLI, ["extract", MAP_PATH, "-o", outDir, "-f", fileInMpq], `提取${fileInMpq}`);
}

function unique(arr) {
  return [...new Set(arr)];
}

async function main() {
  ensureDir(OUT_ROOT);
  const allFiles = listMpqFiles();
  const fileMap = new Map();
  for (const f of allFiles) {
    fileMap.set(f.replace(/\\/g, "/").toLowerCase(), f);
  }
  const byBaseName = new Map();
  for (const f of allFiles) {
    const base = path.basename(f).toLowerCase();
    if (!byBaseName.has(base)) byBaseName.set(base, f);
  }

  const results = [];

  for (const boss of BOSS_MODELS) {
    const modelName = path.basename(boss, ".mdx");
    const modelDir = `${OUT_ROOT}/${modelName}`;
    ensureDir(modelDir);

    const modelPathInMpq =
      fileMap.get(boss.toLowerCase()) || byBaseName.get(path.basename(boss).toLowerCase());
    if (!modelPathInMpq) {
      results.push({ model: boss, ok: false, reason: "地图中未找到该MDX" });
      continue;
    }

    try {
      extractFromMpq(modelPathInMpq, modelDir);
      const localMdxPath = `${modelDir}/${path.basename(modelPathInMpq)}`;
      const mdxData = fs.readFileSync(localMdxPath);
      const model = parseMDX(toArrayBuffer(mdxData));

      const texImages = unique(
        (model.Textures || [])
          .map((t) => (t && t.Image ? String(t.Image).trim() : ""))
          .filter(Boolean)
      );

      for (const tex of texImages) {
        const key = tex.replace(/\\/g, "/").toLowerCase();
        let texPathInMpq = fileMap.get(key);
        if (!texPathInMpq) {
          texPathInMpq = byBaseName.get(path.basename(tex).toLowerCase());
        }
        if (texPathInMpq) {
          extractFromMpq(texPathInMpq, modelDir);
        }
      }

      const outGlb = `${modelDir}/${modelName}.glb`;
      run(
        "node",
        [CONVERTER, "--input", localMdxPath, "--output", outGlb],
        `转换${modelName}到GLB`
      );

      const io = new NodeIO();
      const doc = await io.read(outGlb);
      const root = doc.getRoot();
      results.push({
        model: boss,
        ok: true,
        output: outGlb,
        skins: root.listSkins().length,
        animations: root.listAnimations().length,
        materials: root.listMaterials().length,
        textures: root.listTextures().length,
      });
    } catch (err) {
      results.push({ model: boss, ok: false, reason: String(err.message || err) });
    }
  }

  console.log(JSON.stringify(results, null, 2));
}

main().catch((err) => {
  console.error(String(err && err.message ? err.message : err));
  process.exit(1);
});
