const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function main() {
  const heroImages = readJson("hero_images_manifest_v1.json");
  const terrainImages = readJson("terrain_images_manifest_v1.json");
  const modelCurated = readJson("boss_hero_model_curated_manifest_v1.json");
  const mapDelta = readJson("map_delta_v1.json");

  const out = {
    meta: {
      version: "1.0-godot-asset-map-v1",
      generatedAt: "2026-03-10",
      mapId: 180750
    },
    heroPortraits: (heroImages.heroes || [])
      .filter((x) => x.ok)
      .map((x) => ({
        heroId: x.heroId,
        heroName: x.heroName,
        iconClass: x.iconClass,
        imagePath: x.imagePath
      })),
    terrainImages: (terrainImages.terrains || [])
      .filter((x) => x.ok)
      .map((x) => ({
        terrainId: x.terrainId,
        name: x.name,
        imagePath: x.imagePath
      })),
    modelCurated: (modelCurated.models || []).map((x) => ({
      name: x.name,
      guessClass: x.guessClass,
      guessScore: x.guessScore,
      modelPath: x.curatedPath
    })),
    sourceMapDelta: {
      stats: mapDelta.stats || {},
      bossHeroCandidates: mapDelta.bossHeroCandidates || []
    }
  };

  out.sanity = {
    heroPortraitCount: out.heroPortraits.length,
    terrainImageCount: out.terrainImages.length,
    curatedModelCount: out.modelCurated.length,
    sourceMapBossHeroCandidateCount: (out.sourceMapDelta.bossHeroCandidates || []).length
  };

  fs.writeFileSync("godot_asset_map_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_asset_map_v1.json generated");
  console.log("GODOT_ASSET_MAP_SANITY", out.sanity);
}

main();
