const fs = require("fs");
const path = require("path");

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function exists(p) {
  return !!p && fs.existsSync(p);
}

function toPngLike(p) {
  return String(p || "").replace(/\\/g, "_").replace(/\.blp$/i, ".png");
}

function main() {
  const bindings = readJson("godot_entity_bindings_v2.json");
  const textureManifest = readJson("godot_texture_manifest_v1.json");
  const textureSet = new Set((textureManifest.rows || []).filter((x) => x.ok).map((x) => path.basename(x.pngPath)));
  const textureDir = "godot-assets/textures";
  if (fs.existsSync(textureDir)) {
    for (const f of fs.readdirSync(textureDir)) {
      if (/\.png$/i.test(f)) textureSet.add(path.basename(f));
    }
  }

  const issues = [];

  for (const b of bindings.bossModelBindings || []) {
    if (!exists(b.modelPath)) {
      issues.push({ type: "boss_model_missing", id: b.bossId, modelPath: b.modelPath });
    }
  }

  for (const h of bindings.heroModelBindings || []) {
    if (!exists(h.modelPath)) {
      issues.push({ type: "hero_model_missing", id: h.heroId, modelPath: h.modelPath });
    }
  }

  for (const a of bindings.abilityEffectBindings || []) {
    const icon = a.iconPath || "";
    if (icon && /\.blp$/i.test(icon)) {
      const pngName = toPngLike(icon);
      const ok = textureSet.has(pngName) || textureSet.has(path.basename(pngName));
      if (!ok) issues.push({ type: "ability_icon_texture_missing", id: a.abilityId, iconPath: icon, expectedPng: pngName });
    }
    for (const r of a.resourcePaths || []) {
      if (/\.blp$/i.test(r.path)) {
        const pngName = toPngLike(r.path);
        const ok = textureSet.has(pngName) || textureSet.has(path.basename(pngName));
        if (!ok) issues.push({ type: "ability_resource_texture_missing", id: a.abilityId, field: r.field, path: r.path, expectedPng: pngName });
      }
    }
  }

  const out = {
    meta: {
      version: "1.0-godot-resource-health-v1",
      generatedAt: "2026-03-10"
    },
    stats: {
      bossBindingCount: (bindings.bossModelBindings || []).length,
      heroBindingCount: (bindings.heroModelBindings || []).length,
      abilityBindingCount: (bindings.abilityEffectBindings || []).length,
      textureCount: textureSet.size,
      issueCount: issues.length
    },
    issues
  };
  fs.writeFileSync("godot_resource_health_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_resource_health_v1.json generated");
  console.log("RESOURCE_HEALTH_STATS", out.stats);
}

main();
