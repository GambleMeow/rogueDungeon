const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function assert(cond, msg, errors) {
  if (!cond) errors.push(msg);
}

function main() {
  const errors = [];
  const b = readJson("runtime_bundle_v1.json");

  const hero = b?.runtime?.hero || {};
  const boss = b?.runtime?.boss || {};
  const terrain = b?.runtime?.terrain || {};
  const campaign = b?.runtime?.campaign || {};
  const assets = b?.runtime?.assets || {};
  const sourceMapDelta = b?.runtime?.sourceMapDelta || {};

  const heroes = hero.heroes || [];
  const actionCatalog = hero.actionCatalog || [];
  const replacements = hero.replacementRules || [];
  const waves = boss.waves || [];
  const bosses = boss.bosses || [];
  const bossBehavior21 = boss.bossBehavior21 || [];
  const terrainTemplates = terrain.templates || [];
  const terrainWaves = terrain.waves || [];
  const terrainInstances = terrain.instances || [];
  const terrainRules = terrain.actionRules || [];
  const endgameWaveOverrides = campaign.endgameWaveOverrides || [];
  const progression = campaign.progression || {};
  const sourceMapBossHeroCandidates = sourceMapDelta.bossHeroCandidates || [];

  assert(heroes.length === 43, `hero count expected 43 got ${heroes.length}`, errors);
  assert(waves.length === 21, `wave count expected 21 got ${waves.length}`, errors);
  assert(actionCatalog.length >= 5, `action catalog too small: ${actionCatalog.length}`, errors);
  assert(replacements.length > 100, `replacement rules too small: ${replacements.length}`, errors);
  assert(bosses.length >= 21, `boss entries too small: ${bosses.length}`, errors);
  assert(bossBehavior21.length >= 21, `boss behavior entries too small: ${bossBehavior21.length}`, errors);
  assert(terrainTemplates.length >= 3, `terrain templates too small: ${terrainTemplates.length}`, errors);
  assert(terrainWaves.length >= 21, `terrain wave mapping too small: ${terrainWaves.length}`, errors);
  assert(terrainInstances.length >= 3, `terrain instances too small: ${terrainInstances.length}`, errors);
  assert(terrainRules.length >= 3, `terrain action rules too small: ${terrainRules.length}`, errors);
  for (const t of terrainInstances) {
    assert(!!t.imagePath, `terrain ${t.terrainId} missing imagePath`, errors);
  }
  assert(endgameWaveOverrides.length >= 3, `endgame overrides too small: ${endgameWaveOverrides.length}`, errors);
  assert(
    typeof progression.baseEconomyGrowthPerWave === "number",
    "campaign progression.baseEconomyGrowthPerWave missing",
    errors
  );
  assert(
    Number(assets.bossHeroModelCuratedCount || 0) >= 1,
    `bossHeroModelCuratedCount invalid: ${assets.bossHeroModelCuratedCount}`,
    errors
  );
  assert(
    Number(assets.godotModelPackTextureCount || 0) >= 1,
    `godotModelPackTextureCount invalid: ${assets.godotModelPackTextureCount}`,
    errors
  );
  assert(
    Number(assets.godotModelJsonCount || 0) >= 1,
    `godotModelJsonCount invalid: ${assets.godotModelJsonCount}`,
    errors
  );
  assert(
    Number(assets.godotHeroBindingCount || 0) >= 40,
    `godotHeroBindingCount too small: ${assets.godotHeroBindingCount}`,
    errors
  );
  assert(
    Number(assets.godotBossBindingCount || 0) >= 21,
    `godotBossBindingCount too small: ${assets.godotBossBindingCount}`,
    errors
  );
  assert(
    Number(assets.godotAbilityEffectBindingCount || 0) >= 300,
    `godotAbilityEffectBindingCount too small: ${assets.godotAbilityEffectBindingCount}`,
    errors
  );
  assert(
    Number(assets.godotResourceUnresolvedCount ?? 999999) === 0,
    `godotResourceUnresolvedCount not zero: ${assets.godotResourceUnresolvedCount}`,
    errors
  );
  assert(
    sourceMapBossHeroCandidates.length >= 1,
    `sourceMapDelta bossHeroCandidates too small: ${sourceMapBossHeroCandidates.length}`,
    errors
  );

  const actionIds = new Set(actionCatalog.map((x) => x.actionId));
  for (const h of heroes) {
    assert(!!h.iconClass, `hero ${h.heroId} missing iconClass`, errors);
    assert(!!h.imagePath, `hero ${h.heroId} missing imagePath`, errors);
    const actions = h.actionBindings || [];
    assert(actions.length > 0, `hero ${h.heroId} has no actionBindings`, errors);
    for (const a of actions) {
      assert(actionIds.has(a.actionId), `hero ${h.heroId} action ${a.actionId} missing in catalog`, errors);
      assert(!!a.skillSlot, `hero ${h.heroId} action ${a.actionId} missing skillSlot`, errors);
      assert(!!a.animationTag, `hero ${h.heroId} action ${a.actionId} missing animationTag`, errors);
      assert(typeof a.priority === "number", `hero ${h.heroId} action ${a.actionId} priority invalid`, errors);
    }
  }

  const waveIds = new Set(waves.map((w) => w.bossId));
  const bossIds = new Set(bosses.map((x) => x.id));
  for (const id of waveIds) {
    assert(bossIds.has(id), `wave references unknown bossId ${id}`, errors);
  }

  if (errors.length > 0) {
    console.log("RUNTIME_VALIDATE_FAIL");
    for (const e of errors) console.log("-", e);
    process.exit(1);
  } else {
    console.log("RUNTIME_VALIDATE_OK");
  }
}

main();
