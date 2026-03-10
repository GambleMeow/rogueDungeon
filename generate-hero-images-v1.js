const fs = require("fs");
const https = require("https");
const path = require("path");
const { PNG } = require("pngjs");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      url,
      {
        method: "GET",
        headers: {
          "User-Agent": "Mozilla/5.0",
          Referer: "https://rouge.wiki/",
          Origin: "https://rouge.wiki"
        }
      },
      (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} for ${url}`));
          return;
        }
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => resolve(Buffer.concat(chunks)));
      }
    );
    req.on("error", reject);
    req.end();
  });
}

function parseIconRule(cssText, iconClass) {
  const esc = iconClass.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`\\.${esc}\\{([^}]*)\\}`);
  const m = cssText.match(re);
  if (!m) return null;
  const body = m[1];
  const img = body.match(/background-image:url\(([^)]+)\)/);
  const pos = body.match(/background-position:([-0-9.]+)px\s+([-0-9.]+)px/);
  const w = body.match(/width:([0-9.]+)px/);
  const h = body.match(/height:([0-9.]+)px/);
  if (!img || !pos || !w || !h) return null;
  return {
    spriteUrl: img[1].replace(/^['"]|['"]$/g, ""),
    x: Math.abs(Number(pos[1])),
    y: Math.abs(Number(pos[2])),
    width: Number(w[1]),
    height: Number(h[1])
  };
}

function cropPng(spritePng, x, y, width, height) {
  const out = new PNG({ width, height });
  for (let cy = 0; cy < height; cy++) {
    for (let cx = 0; cx < width; cx++) {
      const srcIdx = ((y + cy) * spritePng.width + (x + cx)) * 4;
      const dstIdx = (cy * width + cx) * 4;
      out.data[dstIdx] = spritePng.data[srcIdx];
      out.data[dstIdx + 1] = spritePng.data[srcIdx + 1];
      out.data[dstIdx + 2] = spritePng.data[srcIdx + 2];
      out.data[dstIdx + 3] = spritePng.data[srcIdx + 3];
    }
  }
  return PNG.sync.write(out);
}

async function main() {
  const heroes = readJson("hero_static_data.json").data || [];
  const css = fs.readFileSync("index-StxNz93E.css", "utf8");
  const outDir = "hero-images";
  fs.mkdirSync(outDir, { recursive: true });

  const bySprite = new Map();
  const entries = [];
  for (const h of heroes) {
    const iconClass = String(h.iconClass || "").trim();
    const rule = parseIconRule(css, iconClass);
    if (!rule) {
      entries.push({
        heroId: h.id,
        heroName: h.name,
        iconClass,
        ok: false,
        reason: "icon rule not found"
      });
      continue;
    }
    if (!bySprite.has(rule.spriteUrl)) bySprite.set(rule.spriteUrl, []);
    bySprite.get(rule.spriteUrl).push({
      heroId: h.id,
      heroName: h.name,
      iconClass,
      ...rule
    });
  }

  for (const [spriteUrl, list] of bySprite) {
    let buf;
    try {
      buf = await fetchBuffer(spriteUrl);
    } catch (e) {
      const urlNoQuery = spriteUrl.split("?")[0];
      buf = await fetchBuffer(urlNoQuery);
    }
    const sprite = PNG.sync.read(buf);
    for (const it of list) {
      const pngBuf = cropPng(sprite, it.x, it.y, it.width, it.height);
      const fileName = `${String(it.heroId).padStart(3, "0")}_${it.iconClass}.png`;
      const filePath = path.join(outDir, fileName);
      fs.writeFileSync(filePath, pngBuf);
      entries.push({
        heroId: it.heroId,
        heroName: it.heroName,
        iconClass: it.iconClass,
        spriteUrl,
        rect: { x: it.x, y: it.y, width: it.width, height: it.height },
        imagePath: filePath.replace(/\\/g, "/"),
        ok: true
      });
    }
  }

  entries.sort((a, b) => Number(a.heroId) - Number(b.heroId));
  const okCount = entries.filter((x) => x.ok).length;
  const out = {
    meta: {
      version: "1.0-hero-images-v1",
      generatedAt: "2026-03-10",
      heroCount: heroes.length,
      okCount,
      failedCount: heroes.length - okCount
    },
    heroes: entries
  };
  fs.writeFileSync("hero_images_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("hero_images_manifest_v1.json generated");
  console.log("HERO_IMAGE_SUMMARY", out.meta);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
