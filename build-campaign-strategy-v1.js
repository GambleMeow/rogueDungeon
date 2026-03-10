const fs = require("fs");

function main() {
  const out = {
    meta: {
      version: "1.0-campaign-strategy-v1",
      generatedAt: "2026-03-10",
      mapId: 180750
    },
    teamSelection: {
      fatiguePenaltyPerUse: 2.1,
      failedTeamPenalty: 3.0,
      endgameDefenseBonus: 4.0,
      endgameMoveBonus: 3.0,
      randomRepositionSummonerPenalty: 8.0,
      forceDefenseAtWaveGte: 16,
      forceMobilityAtWaveGte: 16
    },
    progression: {
      baseEconomyGrowthPerWave: 0.04,
      baseHpGrowthPerWave: 0.03,
      streakDamageGrowth: 0.03,
      streakHpGrowth: 0.02,
      catchupDamageMultiplierOnLose: 1.1,
      catchupHpMultiplierOnLose: 1.08,
      replanBoostPerFail: 0.025,
      replanBoostCap: 0.08,
      loseChainBoostPerFail: 0.03,
      loseChainBoostCap: 0.08,
      lateWaveStart: 12,
      lateWaveDamageBoostPerWave: 0.02,
      lateWaveHpBoost: 1.05
    },
    terrainAdaptation: {
      arena_random_reposition: { damageMul: 1.06, hpMul: 1.05, requireMoveCount: 2, maxSummonerCount: 1 },
      arena_circle_warning: { damageMul: 1.03, hpMul: 1.04, requireDefenseCount: 2 },
      arena_edge_risky: { damageMul: 1.02, hpMul: 1.03, requireDefenseCount: 1 }
    },
    endgameWaveOverrides: [
      { wave: 16, damageMul: 1.05, hpMul: 1.04, requireDefenseCount: 1, requireMoveCount: 1 },
      { wave: 18, damageMul: 1.07, hpMul: 1.05, requireDefenseCount: 1, requireMoveCount: 1 },
      { wave: 19, damageMul: 1.07, hpMul: 1.05, requireDefenseCount: 1, requireMoveCount: 1 },
      { wave: 20, damageMul: 1.08, hpMul: 1.06, requireDefenseCount: 1, requireMoveCount: 1 }
    ],
    bossOverrides: {
      boss_18: { damageMul: 1.03, hpMul: 1.03 },
      boss_19: { damageMul: 1.03, hpMul: 1.03 },
      boss_20: { damageMul: 1.04, hpMul: 1.03 }
    }
  };

  fs.writeFileSync("campaign_strategy_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("campaign_strategy_v1.json generated");
}

main();
