const fs = require('fs');
const path = 'C:/Users/Administrator/.cursor/projects/c-Users-Administrator-Desktop-personal-rogueDungeon/agent-tools/ecf07c4c-e523-411c-89a8-14c0ef11d39e.txt';
const raw = JSON.parse(fs.readFileSync(path, 'utf8'));
const data = raw.data || raw;

// 1) 43 heroes
const heroes = (data || []).map(h => ({ id: h.id, name: h.name, guideCount: h.guideCount || 0 }));

// 2) Global stats
let totalAccessories = 0;
let totalTalents = 0;
let baseTalentCount = 0;
let talentReplacementsCount = 0;
const allTalents = [];
const allReplacements = [];

(data || []).forEach(h => {
  totalAccessories += (h.accessories || []).length;
  (h.talents || []).forEach(t => {
    totalTalents++;
    allTalents.push({ ...t, heroId: h.id });
    if (t.baseTalent === true) baseTalentCount++;
  });
  (h.talentReplacements || []).forEach(r => {
    talentReplacementsCount++;
    allReplacements.push({ ...r, heroId: h.id });
  });
});

// 3) talentReplacements analysis
const priorityDist = {};
allReplacements.forEach(r => {
  const p = r.priority ?? 'undefined';
  priorityDist[p] = (priorityDist[p] || 0) + 1;
});

let emptyTrigger = 0, nonEmptyTrigger = 0;
allReplacements.forEach(r => {
  const ids = r.triggerAccessoryIds;
  if (!ids || ids.length === 0) emptyTrigger++;
  else nonEmptyTrigger++;
});

const heroReplacementCount = {};
allReplacements.forEach(r => {
  heroReplacementCount[r.heroId] = (heroReplacementCount[r.heroId] || 0) + 1;
});
const top10HeroesByReplacements = Object.entries(heroReplacementCount)
  .sort((a, b) => b[1] - a[1])
  .slice(0, 10)
  .map(([heroId, count]) => {
    const hero = data.find(h => h.id == heroId);
    return { heroId: Number(heroId), heroName: hero?.name, count };
  });

// 4) 3 sample heroes full structure
const sampleIds = data?.slice(0, 3).map(h => h.id) || [];
const samples = (data || [])
  .filter(h => sampleIds.includes(h.id))
  .map(h => ({
    ...h,
    accessories: (h.accessories || []).slice(0, 20),
    talents: (h.talents || []).slice(0, 10),
    talentReplacements: (h.talentReplacements || []).slice(0, 10)
  }));

// 5) Godot algorithm suggestion (text)
const godotAdvice = {
  title: "天赋池生成算法建议 (Godot)",
  steps: [
    "1. 升级时先收集所有 baseTalent=true 的天赋作为基础候选池",
    "2. 遍历 talentReplacements：若玩家当前配件包含 triggerAccessoryIds 中任一，则用 replacementTalentId 替换原天赋（或加入替换候选）",
    "3. 按 priority 排序 replacement 规则，高 priority 优先应用",
    "4. 三选一：从最终候选池随机/加权抽取3个不重复天赋展示",
    "5. 注意：同一 baseTalent 可能被多条 replacement 规则覆盖，需按 priority 决定最终展示哪个"
  ],
  pseudoCode: `
func get_upgrade_candidates(hero_id: String, current_accessory_ids: Array) -> Array:
  var base_pool = get_talents_with_base_true(hero_id)
  var replacements = get_talent_replacements(hero_id)
  replacements.sort_custom(func(a,b): return a.priority > b.priority)
  for r in replacements:
    if current_accessory_ids.has_any(r.triggerAccessoryIds):
      base_pool = replace_talent(base_pool, r.baseTalentId, r.replacementTalentId)
  return base_pool
`
};

const result = {
  "1_heroes": heroes,
  "2_global_stats": {
    totalAccessories,
    totalTalents,
    baseTalentCount,
    talentReplacementsCount
  },
  "3_talentReplacements_analysis": {
    priorityDistribution: priorityDist,
    triggerAccessoryIds_empty: emptyTrigger,
    triggerAccessoryIds_nonEmpty: nonEmptyTrigger,
    top10_heroes_by_replacement_count: top10HeroesByReplacements
  },
  "4_sample_heroes_full_structure": samples,
  "5_godot_talent_pool_algorithm": godotAdvice
};

console.log(JSON.stringify(result, null, 2));
