import fs from "fs";
import path from "path";
import War3Map from "w3x-parser";

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function isTrigStr(v) {
  return typeof v === "string" && /^TRIGSTR_\d+$/i.test(v);
}

function trigIndex(v) {
  return Number(String(v).replace(/TRIGSTR_/i, ""));
}

function resolveValue(v, stringMap) {
  if (!isTrigStr(v)) return v;
  const n = trigIndex(v);
  return stringMap[n] || v;
}

function collectObjects(table, modType, stringMap) {
  const out = [];
  const objs = table?.objects || [];
  for (const o of objs) {
    const mods = [];
    for (const m of o.modifications || []) {
      mods.push({
        id: m.id,
        variableType: m.variableType,
        levelOrVariation: m.levelOrVariation,
        dataPointer: m.dataPointer,
        value: resolveValue(m.value, stringMap),
        rawValue: m.value
      });
    }
    out.push({
      modType,
      oldId: o.oldId,
      newId: o.newId,
      modifications: mods
    });
  }
  return out;
}

function firstModValue(mods, key) {
  const x = mods.find((m) => m.id === key);
  return x ? x.value : "";
}

function guessClassByUnit(unit) {
  const name = String(unit.name || "").toLowerCase();
  const model = String(unit.modelPath || "").toLowerCase();
  let scoreBoss = 0;
  let scoreHero = 0;
  if (model.startsWith("units\\") && model.includes("\\hero")) scoreHero += 4;
  if (model.includes("boss")) scoreBoss += 4;
  if (model.startsWith("abilities\\")) {
    scoreBoss -= 2;
    scoreHero -= 2;
  }
  if (/boss|魔王|领主|巫妖|蛛|恐惧|archmage|lich|forest/i.test(name)) scoreBoss += 4;
  if (/hero|祭司|骑士|法师|hunter|warden|invoker|death_knight/i.test(name)) scoreHero += 4;
  if (/boss/i.test(model)) scoreBoss += 3;
  if (/hero/i.test(model)) scoreHero += 3;
  if (scoreBoss === 0 && scoreHero === 0) return { guess: "unknown", score: 0 };
  if (scoreBoss > scoreHero) return { guess: "boss", score: scoreBoss };
  if (scoreHero > scoreBoss) return { guess: "hero", score: scoreHero };
  return { guess: "boss_or_hero", score: scoreBoss };
}

function main() {
  const mapPath = path.resolve("map-archive-extract/3DMGAME-KKrgdlV29982/1462FAF4C66A5DA039CC9CC506A457EB.w3x");
  const map = new War3Map(toArrayBuffer(fs.readFileSync(mapPath)), true);
  const mods = map.readModifications() || {};
  const wts = map.readStringTable();
  const stringMap = wts?.stringMap ? Object.fromEntries(wts.stringMap.entries()) : {};

  const modTypes = ["w3u", "w3a", "w3d", "w3h", "w3q", "w3t", "w3b"];
  const all = {};
  for (const t of modTypes) {
    const node = mods[t];
    all[t] = {
      original: collectObjects(node?.originalTable, t, stringMap),
      custom: collectObjects(node?.customTable, t, stringMap)
    };
  }

  const unitCustom = all.w3u.custom || [];
  const unitLight = unitCustom.map((u) => {
    const name = firstModValue(u.modifications, "unam");
    const modelPath = firstModValue(u.modifications, "umdl");
    const iconPath = firstModValue(u.modifications, "uico");
    const moveSpeed = firstModValue(u.modifications, "umvs");
    const hp = firstModValue(u.modifications, "uhpm");
    const g = guessClassByUnit({ name, modelPath });
    return {
      oldId: u.oldId,
      newId: u.newId,
      name,
      modelPath,
      iconPath,
      hp,
      moveSpeed,
      guessClass: g.guess,
      guessScore: g.score
    };
  });

  const highConfBossHero = unitLight.filter((x) => x.guessScore >= 3 && x.guessClass !== "unknown");

  const out = {
    meta: {
      version: "1.0-map-delta-v1",
      generatedAt: "2026-03-10",
      sourceMapPath: mapPath.replace(/\\/g, "/")
    },
    stats: {
      stringCount: Object.keys(stringMap).length,
      unitCustomCount: all.w3u.custom.length,
      abilityCustomCount: all.w3a.custom.length,
      doodadCustomCount: all.w3d.custom.length,
      buffCustomCount: all.w3h.custom.length,
      upgradeCustomCount: all.w3q.custom.length,
      itemCustomCount: all.w3t.custom.length,
      destructableCustomCount: all.w3b.custom.length,
      bossHeroCandidateCount: highConfBossHero.length
    },
    unitLight,
    bossHeroCandidates: highConfBossHero,
    raw: all
  };

  fs.writeFileSync("map_delta_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("map_delta_v1.json generated");
  console.log("MAP_DELTA_STATS", out.stats);
}

main();
