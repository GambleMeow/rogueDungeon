const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");

const SIZE = 512;
const PAD = 24;

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function toPx(v) {
  return Math.round(PAD + (Number(v) / 100) * (SIZE - PAD * 2));
}

function blendPixel(img, x, y, rgba) {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return;
  const idx = (y * img.width + x) * 4;
  const srcA = rgba[3] / 255;
  const dstA = img.data[idx + 3] / 255;
  const outA = srcA + dstA * (1 - srcA);
  if (outA <= 0) return;
  img.data[idx] = Math.round((rgba[0] * srcA + img.data[idx] * dstA * (1 - srcA)) / outA);
  img.data[idx + 1] = Math.round((rgba[1] * srcA + img.data[idx + 1] * dstA * (1 - srcA)) / outA);
  img.data[idx + 2] = Math.round((rgba[2] * srcA + img.data[idx + 2] * dstA * (1 - srcA)) / outA);
  img.data[idx + 3] = Math.round(outA * 255);
}

function fill(img, rgba) {
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      const i = (y * img.width + x) * 4;
      img.data[i] = rgba[0];
      img.data[i + 1] = rgba[1];
      img.data[i + 2] = rgba[2];
      img.data[i + 3] = rgba[3];
    }
  }
}

function drawRect(img, x, y, w, h, rgba) {
  const x1 = Math.max(0, Math.min(img.width - 1, x));
  const y1 = Math.max(0, Math.min(img.height - 1, y));
  const x2 = Math.max(0, Math.min(img.width - 1, x + w));
  const y2 = Math.max(0, Math.min(img.height - 1, y + h));
  for (let py = y1; py <= y2; py++) {
    for (let px = x1; px <= x2; px++) blendPixel(img, px, py, rgba);
  }
}

function drawCircle(img, cx, cy, r, rgba, filled = true) {
  const minX = Math.max(0, cx - r);
  const maxX = Math.min(img.width - 1, cx + r);
  const minY = Math.max(0, cy - r);
  const maxY = Math.min(img.height - 1, cy + r);
  const rr = r * r;
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy);
      if (filled) {
        if (d2 <= rr) blendPixel(img, x, y, rgba);
      } else if (Math.abs(Math.sqrt(d2) - r) <= 1.5) {
        blendPixel(img, x, y, rgba);
      }
    }
  }
}

function drawLine(img, x1, y1, x2, y2, thickness, rgba) {
  const steps = Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1), 1);
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const x = Math.round(x1 + (x2 - x1) * t);
    const y = Math.round(y1 + (y2 - y1) * t);
    drawCircle(img, x, y, Math.max(1, Math.floor(thickness / 2)), rgba, true);
  }
}

function drawRing(img, cx, cy, rMin, rMax, rgba) {
  const minX = Math.max(0, cx - rMax);
  const maxX = Math.min(img.width - 1, cx + rMax);
  const minY = Math.max(0, cy - rMax);
  const maxY = Math.min(img.height - 1, cy + rMax);
  const rMin2 = rMin * rMin;
  const rMax2 = rMax * rMax;
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy);
      if (d2 >= rMin2 && d2 <= rMax2) blendPixel(img, x, y, rgba);
    }
  }
}

function drawFan(img, cx, cy, r, angleDeg, rgba) {
  const half = (angleDeg / 2) * (Math.PI / 180);
  const dir = Math.PI; // 面向左侧
  for (let y = cy - r; y <= cy + r; y++) {
    for (let x = cx - r; x <= cx + r; x++) {
      const dx = x - cx;
      const dy = y - cy;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d > r || d < 1) continue;
      const a = Math.atan2(dy, dx);
      let da = Math.abs(a - dir);
      if (da > Math.PI) da = 2 * Math.PI - da;
      if (da <= half) blendPixel(img, x, y, rgba);
    }
  }
}

function drawZones(img, instance) {
  for (const b of instance.blockers || []) {
    const cx = toPx(b.x);
    const cy = toPx(b.y);
    const w = Math.max(2, Math.round((Number(b.w || 4) / 100) * (SIZE - PAD * 2)));
    const h = Math.max(2, Math.round((Number(b.h || 4) / 100) * (SIZE - PAD * 2)));
    drawRect(img, Math.round(cx - w / 2), Math.round(cy - h / 2), w, h, [80, 84, 94, 230]);
  }

  for (const z of instance.warningZones || []) {
    const t = String(z.type || "");
    if (t === "circle_warning") {
      drawCircle(img, toPx(z.cx), toPx(z.cy), Math.max(2, Math.round((z.r / 100) * (SIZE - PAD * 2))), [255, 99, 71, 110], true);
    } else if (t === "line_lane") {
      drawLine(img, toPx(z.x1), toPx(z.y1), toPx(z.x2), toPx(z.y2), 8, [255, 140, 0, 150]);
    } else if (t === "frontal_fan_zone") {
      drawFan(img, toPx(z.cx), toPx(z.cy), Math.max(4, Math.round((z.radius / 100) * (SIZE - PAD * 2))), Number(z.angleDeg || 70), [255, 69, 0, 110]);
    } else if (t === "reposition_hotspots") {
      for (const p of z.points || []) drawCircle(img, toPx(p.x), toPx(p.y), 12, [255, 215, 0, 140], true);
    } else if (t === "edge_risk" && z.edge === "right") {
      drawRect(img, toPx(82), PAD, toPx(100) - toPx(82), SIZE - PAD * 2, [255, 69, 58, 95]);
    }
  }

  for (const s of instance.safeZones || []) {
    const t = String(s.type || "");
    if (t === "open_band" || t === "gap_between_rings") {
      drawRect(
        img,
        toPx(s.xMin),
        toPx(s.yMin),
        toPx(s.xMax) - toPx(s.xMin),
        toPx(s.yMax) - toPx(s.yMin),
        [46, 204, 113, 90]
      );
    } else if (t === "ring_lane") {
      drawRing(
        img,
        toPx(s.cx),
        toPx(s.cy),
        Math.max(2, Math.round((s.rMin / 100) * (SIZE - PAD * 2))),
        Math.max(3, Math.round((s.rMax / 100) * (SIZE - PAD * 2))),
        [52, 152, 219, 85]
      );
    }
  }
}

function drawMarkers(img, instance) {
  for (const p of instance.heroSpawnPoints || []) {
    drawCircle(img, toPx(p.x), toPx(p.y), 7, [52, 152, 219, 255], true);
    drawCircle(img, toPx(p.x), toPx(p.y), 9, [255, 255, 255, 220], false);
  }
  if (instance.bossSpawnPoint) {
    drawCircle(img, toPx(instance.bossSpawnPoint.x), toPx(instance.bossSpawnPoint.y), 9, [231, 76, 60, 255], true);
    drawCircle(img, toPx(instance.bossSpawnPoint.x), toPx(instance.bossSpawnPoint.y), 12, [255, 255, 255, 220], false);
  }
  if (instance.objectivePoint) {
    drawCircle(img, toPx(instance.objectivePoint.x), toPx(instance.objectivePoint.y), 6, [241, 196, 15, 255], true);
  }
}

function main() {
  const instances = readJson("terrain_instances_v1.json").terrainInstances || [];
  const outDir = "terrain-images";
  fs.mkdirSync(outDir, { recursive: true });

  const rows = [];
  for (const t of instances) {
    const img = new PNG({ width: SIZE, height: SIZE });
    fill(img, [24, 28, 36, 255]);
    drawRect(img, PAD, PAD, SIZE - PAD * 2, SIZE - PAD * 2, [38, 44, 56, 255]);
    drawZones(img, t);
    drawMarkers(img, t);

    const fileName = `${t.terrainId}.png`;
    const filePath = path.join(outDir, fileName);
    fs.writeFileSync(filePath, PNG.sync.write(img));

    rows.push({
      terrainId: t.terrainId,
      name: t.name,
      tags: t.tags || [],
      imagePath: filePath.replace(/\\/g, "/"),
      size: { width: SIZE, height: SIZE },
      ok: true
    });
  }

  const out = {
    meta: {
      version: "1.0-terrain-images-v1",
      generatedAt: "2026-03-10",
      terrainCount: instances.length,
      okCount: rows.length,
      failedCount: 0
    },
    terrains: rows
  };
  fs.writeFileSync("terrain_images_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("terrain_images_manifest_v1.json generated");
  console.log("TERRAIN_IMAGE_SUMMARY", out.meta);
}

main();
