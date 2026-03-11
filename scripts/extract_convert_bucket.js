const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { parseMDX } = require("war3-model");
const { NodeIO } = require("@gltf-transform/core");

const ROOT = "C:/Users/Administrator/Desktop/personal/rogueDungeon2";
const MPQCLI = `${ROOT}/tools/mpqcli.exe`;
const MAP_PATH = `${ROOT}/archive/map_source/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x`;
const MANIFEST = `${ROOT}/outputs/packages/manifest.json`;
const CONVERTER = `${ROOT}/blender_convert.js`;
const OUT_ROOT = `${ROOT}/outputs/packages`;

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (!k.startsWith("--")) continue;
    args[k.slice(2)] = argv[i + 1];
    i++;
  }
  return args;
}

function run(command, args, desc) {
  const r = spawnSync(command, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) {
    throw new Error(`${desc}失败\n${r.stderr || r.stdout || ""}`);
  }
  return r.stdout || "";
}

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function unique(arr) {
  return [...new Set(arr)];
}

function stripMdxExt(name) {
  return String(name || "").replace(/\.mdx$/i, "");
}

function findFirstGlb(dir) {
  if (!fs.existsSync(dir)) return null;
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.toLowerCase().endsWith(".glb"))
    .sort();
  return files.length > 0 ? `${dir}/${files[0]}` : null;
}

async function main() {
  const args = parseArgs(process.argv);
  const bucket = args.bucket || "effects";
  const limit = Number(args.limit || 30);
  const offset = Number(args.offset || 0);

  const manifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  const list = manifest.buckets[bucket];
  if (!list) throw new Error(`未知桶: ${bucket}`);

  const selected = list.slice(offset, offset + limit);
  const allMapFiles = run(MPQCLI, ["list", MAP_PATH])
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter(Boolean);

  const mapByFull = new Map();
  const mapByBase = new Map();
  for (const f of allMapFiles) {
    mapByFull.set(f.replace(/\\/g, "/").toLowerCase(), f);
    const base = path.basename(f).toLowerCase();
    if (!mapByBase.has(base)) mapByBase.set(base, f);
  }

  const io = new NodeIO();
  const results = [];
  const outBucketDir = `${OUT_ROOT}/${bucket}`;
  fs.mkdirSync(outBucketDir, { recursive: true });

  for (const modelPath of selected) {
    const modelName = stripMdxExt(path.basename(modelPath));
    const modelDir = `${outBucketDir}/${modelName}`;
    fs.mkdirSync(modelDir, { recursive: true });

    const mpqModel = mapByFull.get(modelPath.replace(/\\/g, "/").toLowerCase()) || mapByBase.get(path.basename(modelPath).toLowerCase());
    if (!mpqModel) {
      results.push({ model: modelPath, ok: false, reason: "未找到模型" });
      continue;
    }

    try {
      run(MPQCLI, ["extract", MAP_PATH, "-o", modelDir, "-f", mpqModel], `提取${mpqModel}`);
      let localMdx = `${modelDir}/${path.basename(mpqModel)}`;
      if (!fs.existsSync(localMdx)) {
        const mdxFiles = fs
          .readdirSync(modelDir)
          .filter((f) => f.toLowerCase().endsWith(".mdx"));
        if (mdxFiles.length > 0) {
          localMdx = `${modelDir}/${mdxFiles[0]}`;
        }
      }
      if (!fs.existsSync(localMdx)) {
        throw new Error(`提取后未找到MDX文件: ${mpqModel}`);
      }
      const mdxData = fs.readFileSync(localMdx);
      const model = parseMDX(toArrayBuffer(mdxData));
      const textures = unique(
        (model.Textures || [])
          .map((t) => (t && t.Image ? String(t.Image).trim() : ""))
          .filter(Boolean)
      );
      for (const tex of textures) {
        const full = mapByFull.get(tex.replace(/\\/g, "/").toLowerCase()) || mapByBase.get(path.basename(tex).toLowerCase());
        if (full) run(MPQCLI, ["extract", MAP_PATH, "-o", modelDir, "-f", full], `提取贴图${full}`);
      }

      const expectedGlb = `${modelDir}/${modelName}.glb`;
      run("node", [CONVERTER, "--input", localMdx, "--output", expectedGlb], `转换${modelName}`);
      const outGlb = fs.existsSync(expectedGlb) ? expectedGlb : findFirstGlb(modelDir);
      if (!outGlb) {
        throw new Error(`转换完成但未找到GLB产物: ${modelName}`);
      }

      const doc = await io.read(outGlb);
      const root = doc.getRoot();
      results.push({
        model: modelPath,
        ok: true,
        glb: outGlb,
        skins: root.listSkins().length,
        animations: root.listAnimations().length,
        materials: root.listMaterials().length,
        textures: root.listTextures().length,
      });
    } catch (e) {
      results.push({ model: modelPath, ok: false, reason: String(e.message || e) });
    }
  }

  const reportPath = `${outBucketDir}/report_${bucket}_${offset}_${limit}.json`;
  fs.writeFileSync(reportPath, JSON.stringify(results, null, 2), "utf8");
  console.log(`done: ${reportPath}`);
  console.log(JSON.stringify({ bucket, offset, limit, success: results.filter((r) => r.ok).length, total: results.length }, null, 2));
}

main().catch((e) => {
  console.error(String(e.message || e));
  process.exit(1);
});
