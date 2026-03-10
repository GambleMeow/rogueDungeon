/**
 * 抓取 mapId=180750 高相关帖子，提取 Boss 技能与波次证据
 * 不写文件，仅控制台输出
 */
const MAP_ID = 180750;
const KEYWORDS = ['Boss', 'BOSS', '图鉴', '关卡', '波', '深渊', '暗影', '山丘', '圣骑', '巫妖', '吸血', '修补', '憎恶'];
const MAX_TOPICS = 1500;
const BATCH = 20;

function stripHtml(html) {
  if (!html || typeof html !== 'string') return '';
  return html
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&[a-z]+;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function tagCredibility(className) {
  if (className === '攻略') return '攻略';
  if (className === 'bug反馈') return 'bug反馈';
  return '灌水';
}

async function fetchJson(url) {
  const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
  const j = await res.json();
  return j;
}

async function main() {
  const allTopics = [];
  for (let start = 0; start < MAX_TOPICS; start += BATCH) {
    const url = `https://comment-api.kkdzpt.com/api/v1/topic/page_query_topics?mapId=${MAP_ID}&orderType=1&start=${start}&limit=${BATCH}`;
    const j = await fetchJson(url);
    const list = j?.data || [];
    if (list.length === 0) break;
    allTopics.push(...list);
    if (list.length < BATCH) break;
  }

  const filtered = allTopics.filter(t => {
    const title = (t.title || '').toString();
    return KEYWORDS.some(kw => title.includes(kw));
  });

  const bossEvidence = {};
  const waveEvidence = [];

  for (const t of filtered) {
    const topicId = t.topicId;
    let content = t.content || '';
    const className = t.className || '灌水';
    const cred = tagCredibility(className);

    // 尝试 topic_detail（可能 403）
    try {
      const detailUrl = `https://comment-api.kkdzpt.com/api/v1/topic/detail?mapId=${MAP_ID}&topicId=${topicId}`;
      const d = await fetchJson(detailUrl);
      if (d?.status === 200 && d?.data?.content) content = d.data.content;
    } catch (_) {}

    const text = stripHtml(content);
    if (!text) continue;

    const BOSS_NAMES = ['山丘之王','暗影猎手','大萨满','地穴领主','月之女祭司','巫妖','圣骑士','大魔法师','吸血魔王','恶魔猎手','憎恶','修补匠'];
    const BOSS_ALIAS = { '小强':'地穴领主', '白虎':'月之女祭司', '小Y':'暗影猎手' };
    function extractBossName(snippet) {
      // 优先：X号BOSS 后的名称（必须在片段前80字内）
      const head = snippet.slice(0, 100);
      const m = head.match(/(?:\d+号|[一二三四五六七八九十]+号)\s*[Bb][Oo][Ss][Ss]\s*([^技能，。；\s]+)(?:\s*俗称[^\s]+)?/);
      if (m) {
        const raw = m[1].replace(/\s*俗称\S+/, '').trim();
        for (const n of BOSS_NAMES) {
          if (raw.includes(n) || n.includes(raw)) return n;
        }
        for (const [alias, name] of Object.entries(BOSS_ALIAS)) {
          if (raw.includes(alias)) return name;
        }
        return raw || null;
      }
      for (const n of BOSS_NAMES) {
        if (head.includes(n)) return n;
      }
      return null;
    }

    // Boss 技能片段：必须含 X号BOSS+名称 且 技能一/二/三（支持 技能一、 或 技能一 格式）
    const bossSkillRe = /(?:\d+号|[一二三四五六七八九十]+号)\s*[Bb][Oo][Ss][Ss]\s*[^。]{5,200}(?:技能[一二三四五六七八九十\d]+[、\s][^。]{2,100})+/g;
    const waveRe = /(?:第?\s*)?(\d+)\s*波|(\d+)\s*波(?:次)?/g;

    let m;
    const seenInTopic = new Set();
    while ((m = bossSkillRe.exec(text)) !== null) {
      const snippet = m[0];
      const bossName = extractBossName(snippet) || '未知Boss';
      const key = bossName;
      if (!bossEvidence[key]) bossEvidence[key] = [];
      const sig = topicId + '|' + key + '|' + snippet.slice(0, 60);
      if (seenInTopic.has(sig)) continue;
      seenInTopic.add(sig);
      bossEvidence[key].push({ topicId, snippet, cred });
    }

    // 补充：仅当句子以 X号BOSS 开头且含技能描述
    const sentences = text.split(/[。！？\n]/);
    for (const s of sentences) {
      if (!/^\s*(\d+号|[一二三四五六七八九十]+号)\s*[Bb][Oo][Ss][Ss]/.test(s)) continue;
      if (!/技能[一二三四五六七八九十\d]/.test(s)) continue;
      const bossName = extractBossName(s);
      if (!bossName) continue;
      const key = bossName;
      if (!bossEvidence[key]) bossEvidence[key] = [];
      const sig = topicId + '|' + key + '|' + s.slice(0, 60);
      if (seenInTopic.has(sig)) continue;
      seenInTopic.add(sig);
      bossEvidence[key].push({ topicId, snippet: s, cred });
    }

    // 波次
    while ((m = waveRe.exec(text)) !== null) {
      waveEvidence.push({ topicId, snippet: m[0], cred });
    }
  }

  console.log('=== mapId=180750 高相关帖子 Boss/波次 证据聚合 ===\n');
  console.log(`筛选后帖子数: ${filtered.length}\n`);

  console.log('--- 按 Boss 名聚合证据 ---\n');
  for (const [boss, items] of Object.entries(bossEvidence)) {
    console.log(`【${boss}】`);
    for (const e of items) {
      console.log(`  [${e.cred}] topicId=${e.topicId}`);
      console.log(`    原句: ${e.snippet.substring(0, 120)}${e.snippet.length > 120 ? '...' : ''}`);
    }
    console.log('');
  }

  console.log('--- 波次规则证据 ---\n');
  const waveByTopic = {};
  for (const e of waveEvidence) {
    if (!waveByTopic[e.topicId]) waveByTopic[e.topicId] = [];
    waveByTopic[e.topicId].push({ snippet: e.snippet, cred: e.cred });
  }
  for (const [tid, arr] of Object.entries(waveByTopic)) {
    console.log(`topicId=${tid}`);
    for (const x of arr) console.log(`  [${x.cred}] ${x.snippet}`);
    console.log('');
  }
}

main().catch(e => console.error(e));
