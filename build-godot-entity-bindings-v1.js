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
  return t;
}

function scoreBossToModel(bossName, modelName) {
  const b = tokenize(bossName);
  const m = modelTokenSet(modelName);
  let score = 0;
  for (const t of b) {
    if (m.has(t)) score += 2;
  }
  const bn = normalize(bossName);
  const mn = normalize(modelName);
  if (bn.includes("demonhunter") && mn.includes("demonhunter")) score += 6;
  if (bn.includes("archmage") && mn.includes("archmage")) score += 6;
  if (bn.includes("lich") && mn.includes("lich")) score += 6;
  if (bn.includes("priestessmoon") && (mn.includes("warden") || mn.includes("huntress"))) score += 3;
  if (bn.includes("forestwanderer") && mn.includes("spider")) score += 4;
  if (bn.includes("bloodmage") && mn.includes("tyrael")) score += 2;
  if (bn.includes("elementalpanda") && mn.includes("invoker")) score += 2;
  return score;
}

function pickBossBindings(bosses, modelCandidates) {
  const bossLike = modelCandidates.filter((m) => ["boss", "boss_or_hero", "hero"].includes(m.guessClass));
  const used = new Set();
  const out = [];
  for (const b of bosses) {
    let best = null;
    let bestScore = -1;
    for (const m of bossLike) {
      const key = String(m.outPath || m.name);
      if (used.has(key)) continue;
      const s = scoreBossToModel(b.name, m.name) + Number(m.guessScore || 0);
      if (s > bestScore) {
        bestScore = s;
        best = m;
      }
    }
    if (!best) continue;
    used.add(String(best.outPath || best.name));
    out.push({
      bossId: b.id,
      bossName: b.name,
      modelName: best.name,
      modelPath: best.outPath || "",
      confidence: bestScore >= 8 ? "high" : bestScore >= 5 ? "medium" : "low",
      score: bestScore
    });
  }
  return out;
}

function pickHeroBindings(heroes, modelCandidates) {
  const heroLike = modelCandidates.filter((m) => ["hero", "boss_or_hero"].includes(m.guessClass));
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

function extractEffectBindings(mapDelta) {
  const arr = mapDelta?.raw?.w3a?.custom || [];
  const result = [];
  for (const a of arr) {
    const mods = a.modifications || [];
    const get = (id) => {
      const x = mods.find((m) => m.id === id);
      return x ? x.value : "";
    };
    const resourcePaths = [];
    for (const m of mods) {
      const v = String(m.value || "");
      if (/\.(mdx|mdl|blp|dds|tga)$/i.test(v)) {
        resourcePaths.push({ field: m.id, path: v });
      }
    }
    result.push({
      abilityId: a.newId,
      baseAbilityId: a.oldId,
      abilityName: get("anam"),
      iconPath: get("aart"),
      cooldown: get("acdn"),
      manaCost: get("amcs"),
      castRange: get("aran"),
      area: get("aare"),
      targetType: get("atar"),
      animationName: get("aani"),
      resourcePaths
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
  const abilityEffectBindings = extractEffectBindings(mapDelta);

  const out = {
    meta: {
      version: "1.0-godot-entity-bindings-v1",
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

  fs.writeFileSync("godot_entity_bindings_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_entity_bindings_v1.json generated");
  console.log("ENTITY_BINDING_STATS", out.stats);
}

main();
