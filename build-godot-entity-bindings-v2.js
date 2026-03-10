const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function normalize(s) {
  return String(s || "").toLowerCase().replace(/[^a-z0-9_]/g, "");
}

function tokenize(s) {
  return String(s || "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((x) => x.trim())
    .filter(Boolean);
}

function modelTokenSet(name) {
  const t = new Set(tokenize(name));
  const n = normalize(name);
  if (n.includes("demonhunter")) t.add("demon");
  if (n.includes("demonhunter")) t.add("hunter");
  if (n.includes("deathknight")) t.add("death");
  if (n.includes("deathknight")) t.add("knight");
  if (n.includes("archmage")) t.add("archmage");
  if (n.includes("lich")) t.add("lich");
  if (n.includes("warden")) t.add("warden");
  if (n.includes("spider")) t.add("spider");
  if (n.includes("tyrael")) t.add("paladin");
  return t;
}

const BOSS_HINTS = {
  boss_demon_hunter: ["demonhunter"],
  boss_archmage: ["archmage", "invoker"],
  boss_archmage_v2: ["archmage", "invoker"],
  boss_lich: ["lich", "death", "knight"],
  boss_lich_v2: ["lich", "death", "knight"],
  boss_priestess_moon: ["warden", "huntress"],
  boss_priestess_moon_v2: ["warden", "huntress"],
  boss_forest_wanderer: ["spider", "forest", "boss"],
  boss_blood_mage: ["tyrael", "mage", "ragnaros"],
  boss_elemental_panda: ["invoker", "panda", "element"]
};

function scoreBossToModel(bossName, modelName) {
  const b = tokenize(bossName);
  const m = modelTokenSet(modelName);
  let score = 0;
  for (const t of b) {
    if (m.has(t)) score += 2;
  }
  const bn = normalize(bossName);
  const mn = normalize(modelName);
  const hints = BOSS_HINTS[bossName] || [];
  for (const h of hints) {
    if (mn.includes(h)) score += 4;
  }
  if (bn.includes("demonhunter") && mn.includes("demonhunter")) score += 8;
  if (bn.includes("archmage") && (mn.includes("archmage") || mn.includes("invoker"))) score += 8;
  if (bn.includes("lich") && (mn.includes("lich") || mn.includes("deathknight"))) score += 8;
  if (bn.includes("forestwanderer") && mn.includes("spider")) score += 7;
  if (bn.includes("bloodmage") && (mn.includes("tyrael") || mn.includes("mage"))) score += 6;
  return score;
}

function pickBossBindings(bosses, modelCandidates) {
  const pool = modelCandidates.filter((m) => /(mdx|mdl)$/i.test(String(m.name || "")));
  const out = [];
  for (const b of bosses) {
    let best = null;
    let bestScore = -1;
    for (const m of pool) {
      const s = scoreBossToModel(b.name, m.name) + Number(m.guessScore || 0);
      if (s > bestScore) {
        best = m;
        bestScore = s;
      }
    }
    if (!best && pool.length > 0) best = pool[out.length % pool.length];
    if (!best) continue;
    out.push({
      bossId: b.id,
      bossName: b.name,
      modelName: best.name,
      modelPath: best.outPath || "",
      confidence: bestScore >= 10 ? "high" : bestScore >= 6 ? "medium" : "low",
      score: bestScore
    });
  }
  return out;
}

function pickHeroBindings(heroes, modelCandidates) {
  const heroLike = modelCandidates.filter((m) => /(mdx|mdl)$/i.test(String(m.name || "")) && ["hero", "boss_or_hero", "boss"].includes(m.guessClass));
  if (heroLike.length === 0) return [];
  const out = [];
  for (let i = 0; i < heroes.length; i++) {
    const h = heroes[i];
    const m = heroLike[i % heroLike.length];
    out.push({
      heroId: h.heroId,
      heroName: h.heroName,
      modelName: m.name,
      modelPath: m.outPath || "",
      confidence: "low",
      policy: "pool_round_robin"
    });
  }
  return out;
}

function extractAbilityBindings(mapDelta) {
  const arr = mapDelta?.raw?.w3a?.custom || [];
  const result = [];
  for (const a of arr) {
    const mods = a.modifications || [];
    const fields = {};
    const resourcePaths = [];
    for (const m of mods) {
      const key = m.id;
      const val = m.value;
      fields[key] = val;
      if (typeof val === "string" && /\.(mdx|mdl|blp|dds|tga)$/i.test(val)) {
        resourcePaths.push({ field: key, path: val });
      }
    }
    result.push({
      abilityId: a.newId,
      baseAbilityId: a.oldId,
      abilityName: fields.anam || "",
      iconPath: fields.aart || "",
      cooldown: fields.acdn ?? "",
      manaCost: fields.amcs ?? "",
      castRange: fields.aran ?? "",
      area: fields.aare ?? "",
      targetType: fields.atar ?? "",
      animationName: fields.aani || "",
      levels: fields.alev ?? "",
      resourcePaths,
      fields
    });
  }
  return result;
}

function main() {
  const runtime = readJson("runtime_bundle_v1.json");
  const bossSchema = readJson("boss_wave_schema_v1.json");
  const candidates = readJson("boss_hero_model_candidates_v2.json");
  const mapDelta = readJson("map_delta_v1.json");

  const heroes = runtime?.runtime?.hero?.heroes || [];
  const bosses = bossSchema?.bosses || [];
  const modelCandidates = candidates?.candidates || [];

  const bossModelBindings = pickBossBindings(bosses, modelCandidates);
  const heroModelBindings = pickHeroBindings(heroes, modelCandidates);
  const abilityEffectBindings = extractAbilityBindings(mapDelta);

  const out = {
    meta: {
      version: "1.0-godot-entity-bindings-v2",
      generatedAt: "2026-03-10",
      mapId: 180750
    },
    stats: {
      bossModelBindingCount: bossModelBindings.length,
      heroModelBindingCount: heroModelBindings.length,
      abilityEffectBindingCount: abilityEffectBindings.length
    },
    bossModelBindings,
    heroModelBindings,
    abilityEffectBindings
  };

  fs.writeFileSync("godot_entity_bindings_v2.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_entity_bindings_v2.json generated");
  console.log("ENTITY_BINDING_V2_STATS", out.stats);
}

main();
