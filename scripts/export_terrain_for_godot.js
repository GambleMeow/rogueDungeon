const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { PNG } = require("pngjs");

const ROOT = path.resolve(__dirname, "..").replace(/\\/g, "/");
const DEFAULT_MAP = `${ROOT}/archive/map_source/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x`;
const DEFAULT_MPQCLI = `${ROOT}/tools/mpqcli.exe`;
const DEFAULT_OUT = `${ROOT}/outputs/terrain_godot`;

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const key = argv[i];
    if (!key.startsWith("--")) continue;
    args[key.slice(2)] = argv[i + 1];
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

function bufferToArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function rawcodeToString(id) {
  return String(id || "").replace(/\0/g, "");
}

function writeGrayPng8(filePath, width, height, getValueAt) {
  const png = new PNG({ width, height, colorType: 0 });
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;
      png.data[idx] = getValueAt(x, y);
    }
  }
  fs.writeFileSync(filePath, PNG.sync.write(png));
}

function writeGrayPng16(filePath, width, height, getValueAt) {
  const png = new PNG({
    width,
    height,
    colorType: 0,
    bitDepth: 16,
    inputColorType: 0,
    inputHasAlpha: false,
  });
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const p = (y * width + x) * 2;
      const v = getValueAt(x, y);
      png.data[p] = (v >> 8) & 0xff;
      png.data[p + 1] = v & 0xff;
    }
  }
  fs.writeFileSync(filePath, PNG.sync.write(png, { colorType: 0, bitDepth: 16 }));
}

function parseRegionsFromWar3MapJ(jText) {
  const regions = [];
  const reg = /set\s+gg_rct_([A-Za-z0-9_]+)\s*=\s*Rect\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^)]+)\)/g;
  let m;
  while ((m = reg.exec(jText)) !== null) {
    const n = (s) => Number(String(s).replace(/\s+/g, ""));
    const name = `gg_rct_${m[1]}`;
    const minX = n(m[2]);
    const minY = n(m[3]);
    const maxX = n(m[4]);
    const maxY = n(m[5]);
    const war3CenterX = (minX + maxX) * 0.5;
    const war3CenterY = (minY + maxY) * 0.5;
    regions.push({
      name,
      war3: {
        min: [minX, minY],
        max: [maxX, maxY],
        center: [war3CenterX, war3CenterY],
        size: [Math.abs(maxX - minX), Math.abs(maxY - minY)],
      },
      godot: {
        // war3(x,y) -> godot(x,z=-y)
        center: [war3CenterX, -war3CenterY],
        size: [Math.abs(maxX - minX), Math.abs(maxY - minY)],
      },
    });
  }
  return regions;
}

async function main() {
  const args = parseArgs(process.argv);
  const mapPath = args.map || DEFAULT_MAP;
  const mpqcli = args.mpqcli || DEFAULT_MPQCLI;
  const outRoot = args.out || DEFAULT_OUT;
  const rawDir = `${outRoot}/raw`;
  const terrainDir = `${outRoot}/terrain`;

  if (!fs.existsSync(mapPath)) throw new Error(`地图不存在: ${mapPath}`);
  if (!fs.existsSync(mpqcli)) throw new Error(`mpqcli不存在: ${mpqcli}`);

  fs.mkdirSync(rawDir, { recursive: true });
  fs.mkdirSync(terrainDir, { recursive: true });

  const files = ["war3map.w3e", "war3map.wpm", "war3map.doo", "war3map.w3i", "war3map.j"];
  for (const f of files) {
    run(mpqcli, ["extract", mapPath, "-o", rawDir, "-f", f], `提取${f}`);
  }

  const parser = await import("w3x-parser");
  const W3E = parser.w3e.File;
  const WPM = parser.wpm.File;
  const DOO = parser.doo.File;
  const W3I = parser.w3i.File;

  const w3eBuffer = bufferToArrayBuffer(fs.readFileSync(`${rawDir}/war3map.w3e`));
  const wpmBuffer = bufferToArrayBuffer(fs.readFileSync(`${rawDir}/war3map.wpm`));
  const dooBuffer = bufferToArrayBuffer(fs.readFileSync(`${rawDir}/war3map.doo`));
  const w3iBuffer = bufferToArrayBuffer(fs.readFileSync(`${rawDir}/war3map.w3i`));

  const w3e = new W3E(w3eBuffer);
  const wpm = new WPM(wpmBuffer);
  const doo = new DOO(dooBuffer);
  const w3i = new W3I(w3iBuffer);

  const width = w3e.mapSize[0];
  const height = w3e.mapSize[1];

  let minH = Infinity;
  let maxH = -Infinity;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const h = w3e.corners[y][x].groundHeight;
      if (h < minH) minH = h;
      if (h > maxH) maxH = h;
    }
  }
  const hRange = Math.max(0.000001, maxH - minH);

  writeGrayPng16(`${terrainDir}/heightmap_16.png`, width, height, (x, y) => {
    const h = w3e.corners[y][x].groundHeight;
    return Math.max(0, Math.min(65535, Math.round(((h - minH) / hRange) * 65535)));
  });

  writeGrayPng8(`${terrainDir}/heightmap_preview_8.png`, width, height, (x, y) => {
    const h = w3e.corners[y][x].groundHeight;
    return Math.max(0, Math.min(255, Math.round(((h - minH) / hRange) * 255)));
  });

  const pWidth = wpm.size[0];
  const pHeight = wpm.size[1];
  writeGrayPng8(`${terrainDir}/walkable_mask.png`, pWidth, pHeight, (x, y) => {
    const v = wpm.pathing[y * pWidth + x];
    const unwalkable = (v & 0x02) !== 0;
    return unwalkable ? 0 : 255;
  });

  const props = doo.doodads.map((d, i) => {
    const x = d.location[0];
    const y = d.location[1];
    const z = d.location[2];
    return {
      index: i,
      rawcode: rawcodeToString(d.id),
      variation: d.variation,
      war3: {
        position: [x, y, z],
        angle_rad: d.angle,
        scale: [d.scale[0], d.scale[1], d.scale[2]],
      },
      godot: {
        position: [x, z, -y],
        rotation_y_rad: -d.angle,
        scale: [d.scale[0], d.scale[2], d.scale[1]],
      },
      flags: d.flags,
      life: d.life,
      editorId: d.editorId,
    };
  });
  fs.writeFileSync(`${terrainDir}/props.json`, JSON.stringify(props, null, 2), "utf8");
  const jText = fs.readFileSync(`${rawDir}/war3map.j`, "utf8");
  const regions = parseRegionsFromWar3MapJ(jText);
  fs.writeFileSync(`${terrainDir}/regions.json`, JSON.stringify(regions, null, 2), "utf8");

  const metadata = {
    map: mapPath,
    terrain: {
      tileset: w3e.tileset,
      size: [width, height],
      centerOffset: [w3e.centerOffset[0], w3e.centerOffset[1]],
      groundHeightMin: minH,
      groundHeightMax: maxH,
      groundTilesets: w3e.groundTilesets,
      cliffTilesets: w3e.cliffTilesets,
    },
    pathing: {
      size: [pWidth, pHeight],
      note: "walkable_mask 使用 wpm bit 0x02 作为不可行走判定",
    },
    doodads: {
      count: doo.doodads.length,
      terrainDoodads: doo.terrainDoodads.length,
    },
    mapInfo: {
      playableSize: [w3i.playableSize ? w3i.playableSize[0] : null, w3i.playableSize ? w3i.playableSize[1] : null],
      tileset: w3i.tileset || null,
    },
    outputs: {
      height16: `${terrainDir}/heightmap_16.png`,
      heightPreview8: `${terrainDir}/heightmap_preview_8.png`,
      walkableMask: `${terrainDir}/walkable_mask.png`,
      props: `${terrainDir}/props.json`,
      regions: `${terrainDir}/regions.json`,
      raw: rawDir,
    },
  };
  fs.writeFileSync(`${terrainDir}/metadata.json`, JSON.stringify(metadata, null, 2), "utf8");

  console.log(
    JSON.stringify(
      {
        ok: true,
        terrainSize: [width, height],
        pathingSize: [pWidth, pHeight],
        doodads: doo.doodads.length,
        regions: regions.length,
        out: terrainDir,
      },
      null,
      2
    )
  );
}

main().catch((e) => {
  console.error(String(e.message || e));
  process.exit(1);
});
