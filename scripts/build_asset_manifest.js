const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = "C:/Users/Administrator/Desktop/personal/rogueDungeon2";
const MPQCLI = `${ROOT}/tools/mpqcli.exe`;
const MAP_PATH = `${ROOT}/archive/map_source/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x`;
const OUT_DIR = `${ROOT}/outputs/packages`;
const OUT_FILE = `${OUT_DIR}/manifest.json`;

const BUCKET_RULES = [
  {
    name: "effects",
    keywords: [
      "spell",
      "effect",
      "aura",
      "impact",
      "slash",
      "flame",
      "fire",
      "light",
      "void",
      "radiance",
      "blink",
      "storm",
      "shock",
      "beam",
      "arcane",
      "fury",
      "rage",
      "shield",
      "teleport",
      "strike",
      "blizzard",
      "starfall",
      "singularity",
    ],
  },
  {
    name: "projectiles",
    keywords: [
      "missile",
      "arrow",
      "bullet",
      "bolt",
      "shell",
      "cannonball",
      "grenade",
      "spear",
      "shot",
      "thrust",
      "breath",
    ],
  },
  {
    name: "environment",
    keywords: [
      "doodads\\terrain",
      "tree",
      "fountain",
      "door",
      "gate",
      "grave",
      "mineral",
      "spawnmodels",
      "terrain",
      "loading",
    ],
  },
  {
    name: "units",
    keywords: [
      "hero",
      "boss",
      "creeps",
      "units\\",
      "arthas",
      "dragon",
      "serpent",
      "warden",
      "sniper",
      "seawitch",
      "invoker",
      "airen",
      "tyrael",
    ],
  },
];

function run(command, args) {
  const r = spawnSync(command, args, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  if (r.status !== 0) {
    throw new Error(`命令失败: ${command} ${args.join(" ")}\n${r.stderr || r.stdout || ""}`);
  }
  return r.stdout || "";
}

function normalizeKey(filePath) {
  return filePath.replace(/\\/g, "/").toLowerCase();
}

function classify(filePath) {
  const key = normalizeKey(filePath);
  for (const rule of BUCKET_RULES) {
    if (rule.keywords.some((k) => key.includes(k))) return rule.name;
  }
  return "misc";
}

function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const out = run(MPQCLI, ["list", MAP_PATH]);
  const mdxList = out
    .split(/\r?\n/)
    .map((s) => s.trim())
    .filter((s) => s && s.toLowerCase().endsWith(".mdx"));

  const buckets = { effects: [], projectiles: [], environment: [], units: [], misc: [] };
  for (const mdx of mdxList) {
    buckets[classify(mdx)].push(mdx);
  }
  for (const k of Object.keys(buckets)) {
    buckets[k].sort((a, b) => a.localeCompare(b));
  }

  const manifest = {
    map: MAP_PATH,
    totalMdx: mdxList.length,
    counts: Object.fromEntries(Object.entries(buckets).map(([k, v]) => [k, v.length])),
    buckets,
  };

  fs.writeFileSync(OUT_FILE, JSON.stringify(manifest, null, 2), "utf8");
  console.log(JSON.stringify(manifest.counts, null, 2));
  console.log(`manifest: ${OUT_FILE}`);
}

main();
