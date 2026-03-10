const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function main() {
  const rawHeroes = readJson("hero_static_data.json");
  const rawTags = readJson("hero_tags.json");

  const heroes = rawHeroes?.data || [];
  const tags = rawTags?.data || [];

  const heroBrief = [];
  const replacementRules = [];

  let totalAccessories = 0;
  let totalTalents = 0;
  let totalBaseTalents = 0;
  let totalReplacements = 0;

  for (const hero of heroes) {
    const accessories = hero.accessories || [];
    const talents = hero.talents || [];
    const replacements = hero.talentReplacements || [];

    totalAccessories += accessories.length;
    totalTalents += talents.length;
    totalReplacements += replacements.length;

    const baseTalentIds = [];
    for (const t of talents) {
      if (t.baseTalent) {
        totalBaseTalents += 1;
        baseTalentIds.push(t.id);
      }
    }

    heroBrief.push({
      heroId: hero.id,
      heroName: hero.name,
      guideCount: hero.guideCount || 0,
      accessoryCount: accessories.length,
      talentCount: talents.length,
      replacementRuleCount: replacements.length,
      baseTalentIds,
      accessoryIds: accessories.map((x) => x.id),
      talentIds: talents.map((x) => x.id)
    });

    for (const r of replacements) {
      replacementRules.push({
        heroId: hero.id,
        heroName: hero.name,
        baseTalentId: r.baseTalentId,
        replacementTalentId: r.replacementTalentId,
        priority: r.priority ?? 0,
        triggerAccessoryIds: r.triggerAccessoryIds || []
      });
    }
  }

  replacementRules.sort((a, b) => {
    if (a.heroId !== b.heroId) return a.heroId - b.heroId;
    return (b.priority || 0) - (a.priority || 0);
  });

  const schema = {
    meta: {
      version: "1.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      sourceFiles: ["hero_static_data.json", "hero_tags.json"],
      sourceApis: [
        "https://api.rouge.wiki/api/game/static-data",
        "https://api.rouge.wiki/api/tags"
      ]
    },
    globalStats: {
      heroCount: heroes.length,
      totalAccessories,
      totalTalents,
      totalBaseTalents,
      totalReplacementRules: totalReplacements
    },
    heroTags: tags.map((t) => ({
      id: t.id,
      name: t.name,
      color: t.color,
      sortIndex: t.sortIndex,
      status: t.status
    })),
    heroBrief,
    replacementRules,
    godotRuntimeModel: {
      note: "Upgrade candidates are generated from base talents and replacement rules.",
      steps: [
        "Load hero talents where baseTalent=true as base candidate pool.",
        "Filter replacementRules by current hero.",
        "Sort rules by priority desc.",
        "Apply rule when triggerAccessoryIds intersects current accessories.",
        "Replace baseTalentId with replacementTalentId in candidate pool.",
        "Draw 3 non-duplicate talents from final pool."
      ],
      pseudocode: [
        "pool = baseTalents(heroId)",
        "rules = sortByPriorityDesc(replacementRules[heroId])",
        "for rule in rules:",
        "  if intersects(rule.triggerAccessoryIds, currentAccessoryIds):",
        "    pool = replaceTalent(pool, rule.baseTalentId, rule.replacementTalentId)",
        "return pick3(pool)"
      ]
    }
  };

  fs.writeFileSync("hero_system_schema_v1.json", JSON.stringify(schema, null, 2), "utf8");
  console.log("hero_system_schema_v1.json generated");
}

main();
