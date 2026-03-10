const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function tryReadJson(path) {
  try {
    return readJson(path);
  } catch (_) {
    return null;
  }
}

function indexBy(arr, key) {
  const m = {};
  for (const x of arr || []) m[x[key]] = x;
  return m;
}

function buildHeroRuntime(heroSystem, heroV4, heroImages) {
  const briefById = indexBy(heroSystem.heroBrief || [], "heroId");
  const imgById = indexBy((heroImages && heroImages.heroes) || [], "heroId");
  const runtimeHeroes = [];

  for (const h of heroV4.heroActionBindings || []) {
    const brief = briefById[h.heroId] || {};
    const img = imgById[h.heroId] || {};
    runtimeHeroes.push({
      heroId: h.heroId,
      heroName: h.heroName,
      iconClass: img.iconClass || "",
      imagePath: img.imagePath || "",
      combatArchetype: h.combatArchetype,
      damageProfile: h.damageProfile,
      guideCount: brief.guideCount || 0,
      accessoryIds: brief.accessoryIds || [],
      talentIds: brief.talentIds || [],
      behaviorFlags: h.behaviorFlags || {},
      treeConfig: h.treeConfig || {},
      actionBindings: h.actionBindings || []
    });
  }

  return {
    globalStats: heroSystem.globalStats || {},
    actionCatalog: heroV4.actionCatalog || [],
    heroes: runtimeHeroes,
    replacementRules: heroSystem.replacementRules || []
  };
}

function buildBossRuntime(bossSchema) {
  return {
    scaling: bossSchema.scaling || {},
    waves: bossSchema.waves || [],
    waveEvidence: bossSchema.waveEvidence || [],
    bosses: bossSchema.bosses || [],
    bossBehavior21: bossSchema.bossBehavior21 || [],
    bossCatalog31: bossSchema.bossCatalog31 || []
  };
}

function main() {
  const bossSchema = readJson("boss_wave_schema_v1.json");
  const heroSystem = readJson("hero_system_schema_v1.json");
  const heroV4 = readJson("hero_skill_priority_v4.json");
  const terrainSchema = tryReadJson("terrain_schema_v1.json");
  const terrainInstances = tryReadJson("terrain_instances_v1.json");
  const terrainActionRules = tryReadJson("terrain_action_rules_v1.json");
  const terrainImages = tryReadJson("terrain_images_manifest_v1.json");
  const campaignStrategy = tryReadJson("campaign_strategy_v1.json");
  const heroImages = tryReadJson("hero_images_manifest_v1.json");
  const bossHeroModelCandidates = tryReadJson("boss_hero_model_candidates_v2.json");
  const bossHeroModelCurated = tryReadJson("boss_hero_model_curated_manifest_v1.json");
  const mapDelta = tryReadJson("map_delta_v1.json");
  const godotAssetMap = tryReadJson("godot_asset_map_v1.json");
  const godotModelPack = tryReadJson("godot_model_pack_manifest_v1.json");
  const godotModelJson = tryReadJson("godot_model_json_manifest_v1.json");
  const godotEntityBindings =
    tryReadJson("godot_entity_bindings_v2.json") || tryReadJson("godot_entity_bindings_v1.json");
  const godotResourceHealth = tryReadJson("godot_resource_health_v1.json");
  const godotTextureFallback = tryReadJson("godot_texture_fallback_map_v1.json");
  const godotResourceHealthEffective = tryReadJson("godot_resource_health_effective_v1.json");
  const terrainImageById = indexBy((terrainImages && terrainImages.terrains) || [], "terrainId");

  const out = {
    meta: {
      version: "1.0-runtime-bundle",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sources: [
        "boss_wave_schema_v1.json",
        "hero_system_schema_v1.json",
        "hero_skill_priority_v4.json"
      ]
    },
    runtime: {
      hero: buildHeroRuntime(heroSystem, heroV4, heroImages),
      boss: buildBossRuntime(bossSchema),
      terrain: terrainSchema
        ? {
            templates: terrainSchema.templates || [],
            waves: terrainSchema.waves || [],
            bossTerrainHints: terrainSchema.bossTerrainHints || [],
            instances: terrainInstances
              ? (terrainInstances.terrainInstances || []).map((x) => ({
                  ...x,
                  imagePath: (terrainImageById[x.terrainId] || {}).imagePath || ""
                }))
              : [],
            actionRules: terrainActionRules ? terrainActionRules.rules || [] : []
          }
        : {
            templates: [],
            waves: [],
            bossTerrainHints: [],
            instances: [],
            actionRules: []
          },
      campaign: campaignStrategy
        ? {
            teamSelection: campaignStrategy.teamSelection || {},
            progression: campaignStrategy.progression || {},
            terrainAdaptation: campaignStrategy.terrainAdaptation || {},
            endgameWaveOverrides: campaignStrategy.endgameWaveOverrides || [],
            bossOverrides: campaignStrategy.bossOverrides || {}
          }
        : {
            teamSelection: {},
            progression: {},
            terrainAdaptation: {},
            endgameWaveOverrides: [],
            bossOverrides: {}
          },
      assets: {
        heroImageManifest: "hero_images_manifest_v1.json",
        terrainImageManifest: "terrain_images_manifest_v1.json",
        bossHeroModelCandidatesManifest: bossHeroModelCandidates ? "boss_hero_model_candidates_v2.json" : "",
        bossHeroModelCuratedManifest: bossHeroModelCurated ? "boss_hero_model_curated_manifest_v1.json" : "",
        godotAssetMapManifest: godotAssetMap ? "godot_asset_map_v1.json" : "",
        godotModelPackManifest: godotModelPack ? "godot_model_pack_manifest_v1.json" : "",
        godotModelJsonManifest: godotModelJson ? "godot_model_json_manifest_v1.json" : "",
        godotEntityBindingsManifest: godotEntityBindings
          ? (tryReadJson("godot_entity_bindings_v2.json") ? "godot_entity_bindings_v2.json" : "godot_entity_bindings_v1.json")
          : "",
        godotResourceHealthManifest: godotResourceHealth ? "godot_resource_health_v1.json" : "",
        godotTextureFallbackManifest: godotTextureFallback ? "godot_texture_fallback_map_v1.json" : "",
        godotResourceHealthEffectiveManifest: godotResourceHealthEffective
          ? "godot_resource_health_effective_v1.json"
          : "",
        bossHeroModelCandidatesCount: bossHeroModelCandidates ? (bossHeroModelCandidates.candidates || []).length : 0,
        bossHeroModelCuratedCount: bossHeroModelCurated ? (bossHeroModelCurated.models || []).length : 0,
        godotAssetMapModelCount: godotAssetMap ? Number(godotAssetMap?.sanity?.curatedModelCount || 0) : 0,
        godotModelPackModelCount: godotModelPack ? Number(godotModelPack?.stats?.curatedModels || 0) : 0,
        godotModelPackTextureCount: godotModelPack ? Number(godotModelPack?.stats?.textures || 0) : 0,
        godotModelJsonCount: godotModelJson ? Number(godotModelJson?.meta?.okCount || 0) : 0,
        godotBossBindingCount: godotEntityBindings ? Number(godotEntityBindings?.stats?.bossModelBindingCount || 0) : 0,
        godotHeroBindingCount: godotEntityBindings ? Number(godotEntityBindings?.stats?.heroModelBindingCount || 0) : 0,
        godotAbilityEffectBindingCount: godotEntityBindings ? Number(godotEntityBindings?.stats?.abilityEffectBindingCount || 0) : 0,
        godotResourceIssueCount: godotResourceHealth ? Number(godotResourceHealth?.stats?.issueCount || 0) : -1,
        godotFallbackCoverageCount: godotTextureFallback ? Number(godotTextureFallback?.summary?.withFallback || 0) : 0,
        godotResourceUnresolvedCount: godotResourceHealthEffective
          ? Number(godotResourceHealthEffective?.stats?.unresolvedCount || 0)
          : -1
      },
      sourceMapDelta: mapDelta
        ? {
            stats: mapDelta.stats || {},
            bossHeroCandidates: mapDelta.bossHeroCandidates || [],
            unitLight: mapDelta.unitLight || []
          }
        : {
            stats: {},
            bossHeroCandidates: [],
            unitLight: []
          },
      sourceMapDeltaManifest: mapDelta ? "map_delta_v1.json" : "",
      godotEntityBindings: godotEntityBindings
        ? {
            bossModelBindings: godotEntityBindings.bossModelBindings || [],
            heroModelBindings: godotEntityBindings.heroModelBindings || [],
            abilityEffectBindings: godotEntityBindings.abilityEffectBindings || []
          }
        : {
            bossModelBindings: [],
            heroModelBindings: [],
            abilityEffectBindings: []
          },
      godotTextureFallback: godotTextureFallback
        ? {
            fallbackRows: godotTextureFallback.fallbackRows || [],
            summary: godotTextureFallback.summary || {}
          }
        : {
            fallbackRows: [],
            summary: {}
          }
    },
    sanity: {
      heroCount: (heroV4.heroActionBindings || []).length,
      bossWaveCount: (bossSchema.waves || []).length,
      actionCatalogCount: (heroV4.actionCatalog || []).length,
      terrainTemplateCount: terrainSchema ? (terrainSchema.templates || []).length : 0,
      terrainInstanceCount: terrainInstances ? (terrainInstances.terrainInstances || []).length : 0,
      terrainRuleCount: terrainActionRules ? (terrainActionRules.rules || []).length : 0,
      terrainImageCount: terrainImages ? (terrainImages.terrains || []).filter((x) => x.ok).length : 0,
      endgameOverrideCount: campaignStrategy ? (campaignStrategy.endgameWaveOverrides || []).length : 0,
      heroImageCount: heroImages ? (heroImages.heroes || []).filter((x) => x.ok).length : 0,
      bossHeroModelCandidateCount: bossHeroModelCandidates ? (bossHeroModelCandidates.candidates || []).length : 0,
      bossHeroModelCuratedCount: bossHeroModelCurated ? (bossHeroModelCurated.models || []).length : 0,
      sourceMapBossHeroCandidateCount: mapDelta ? (mapDelta.bossHeroCandidates || []).length : 0,
      godotAssetMapModelCount: godotAssetMap ? Number(godotAssetMap?.sanity?.curatedModelCount || 0) : 0,
      godotModelPackModelCount: godotModelPack ? Number(godotModelPack?.stats?.curatedModels || 0) : 0,
      godotModelPackTextureCount: godotModelPack ? Number(godotModelPack?.stats?.textures || 0) : 0,
      godotModelJsonCount: godotModelJson ? Number(godotModelJson?.meta?.okCount || 0) : 0,
      godotBossBindingCount: godotEntityBindings ? Number(godotEntityBindings?.stats?.bossModelBindingCount || 0) : 0,
      godotHeroBindingCount: godotEntityBindings ? Number(godotEntityBindings?.stats?.heroModelBindingCount || 0) : 0,
      godotAbilityEffectBindingCount: godotEntityBindings ? Number(godotEntityBindings?.stats?.abilityEffectBindingCount || 0) : 0,
      godotFallbackCoverageCount: godotTextureFallback ? Number(godotTextureFallback?.summary?.withFallback || 0) : 0,
      godotResourceUnresolvedCount: godotResourceHealthEffective
        ? Number(godotResourceHealthEffective?.stats?.unresolvedCount || 0)
        : -1
    }
  };

  fs.writeFileSync("runtime_bundle_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("runtime_bundle_v1.json generated");
}

main();
