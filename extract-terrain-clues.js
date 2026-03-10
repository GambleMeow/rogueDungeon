const https = require("https");
const fs = require("fs");

const TOPICS = [
  "60038404a4f7ad546d152df9",
  "6089035f15bcad784d0b424e",
  "65151b52cdddb63ebc890efc",
  "652901ba7195182decd4240e",
  "652905cb7195182decd42434",
  "65299d107195182decd42c6e"
];

const KEYWORDS = [
  "边缘", "中心", "外圈", "内圈", "角落", "地形", "卡位", "穿墙", "绕外圈",
  "随机位置", "地图随机", "贴墙", "走位", "范围", "扇形", "直线", "圆形",
  "分散", "集合", "拉开", "拉到", "场地", "终点", "圈", "红圈"
];

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => resolve(data));
      })
      .on("error", reject);
  });
}

function stripHtml(html) {
  return String(html || "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\r/g, "")
    .replace(/\n{2,}/g, "\n")
    .trim();
}

function collectLines(text) {
  return text
    .split("\n")
    .map((x) => x.trim())
    .filter(Boolean);
}

function findClues(lines) {
  const clues = [];
  for (const line of lines) {
    for (const k of KEYWORDS) {
      if (line.includes(k)) {
        clues.push({ keyword: k, clueText: line });
        break;
      }
    }
  }
  return clues;
}

function normalizeTag(text) {
  if (text.includes("边缘") || text.includes("贴墙")) return "edge_hugging";
  if (text.includes("中心")) return "center_control";
  if (text.includes("外圈")) return "outer_ring_pathing";
  if (text.includes("内圈")) return "inner_ring_pathing";
  if (text.includes("角落")) return "corner_risk";
  if (text.includes("卡位")) return "anti_stuck_layout";
  if (text.includes("穿墙")) return "wall_penetration";
  if (text.includes("随机位置") || text.includes("地图随机")) return "random_reposition_pressure";
  if (text.includes("扇形")) return "fan_aoe_facing";
  if (text.includes("直线")) return "line_skill_lane";
  if (text.includes("圆形") || text.includes("圈") || text.includes("红圈")) return "circle_aoe_zone";
  if (text.includes("分散")) return "spread_requirement";
  if (text.includes("集合")) return "stack_requirement";
  if (text.includes("拉开") || text.includes("拉到")) return "kite_and_pull";
  if (text.includes("走位")) return "movement_check";
  return "unknown";
}

async function main() {
  const out = {
    meta: {
      version: "1.0-v1",
      generatedAt: "2026-03-10",
      mapId: 180750,
      source: "comment-api topic_detail"
    },
    topics: [],
    terrainClues: []
  };

  for (const topicId of TOPICS) {
    const url =
      "https://comment-api.kkdzpt.com/api/v1/topic/topic_detail?mapId=180750&topicId=" +
      topicId;
    try {
      const raw = await fetchText(url);
      const json = JSON.parse(raw);
      const data = json?.data || {};
      const text = stripHtml(data.content || "");
      const lines = collectLines(text);
      const clues = findClues(lines).map((c) => ({
        topicId,
        title: data.title || "",
        keyword: c.keyword,
        normalizedTag: normalizeTag(c.clueText),
        clueText: c.clueText
      }));

      out.topics.push({
        topicId,
        title: data.title || "",
        lineCount: lines.length,
        clueCount: clues.length
      });
      out.terrainClues.push(...clues);
    } catch (e) {
      out.topics.push({
        topicId,
        error: e.message
      });
    }
  }

  fs.writeFileSync("terrain_clues_raw_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("terrain_clues_raw_v1.json generated");
}

main();
