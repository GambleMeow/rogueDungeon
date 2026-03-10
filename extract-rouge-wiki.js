/**
 * rouge.wiki 数据提取 - Godot复刻用（完整版）
 * 1) 捕获API 2) DOM抓取+文本解析 3) 机制规则 4) JSON输出
 */
const { chromium } = require('playwright');
const fs = require('fs');

const CATEGORY_MAP = {
  '齿轮': '齿轮', '充能': '充能', '摧毁': '摧毁', '火花': '火花', '结算': '结算',
  '蓝港': '蓝港', '灵魂': '灵魂', '泰坦': '泰坦', '硬币': '硬币', '战旗': '战旗',
  '咒文': '咒文', '邪能': '邪能', '自动': '自动', '中立': '中立', '传火': '传火',
  '毒蛇大师小玩意': '毒蛇大师小玩意', '合成道具': '合成道具', '其他': '其他',
  '诅咒道具': '诅咒道具', '魔戒道具': '魔戒道具'
};

function inferCategory(name, desc) {
  const t = (name + (desc || '')).toLowerCase();
  for (const [k, v] of Object.entries(CATEGORY_MAP)) {
    if (t.includes(k)) return v;
  }
  return null;
}

function parseItemsFromText(text) {
  const items = [];
  const re = /([\u4e00-\u9fa5a-zA-Z0-9（）\-]+?)\s*[（(](\d+|未知)[级)）]\s*(?:\s*\n|★)?/g;
  let match;
  const positions = [];
  while ((match = re.exec(text)) !== null) {
    positions.push({ name: match[1].trim(), level: match[2], index: match.index });
  }
  const skip = ['流派','等级','选项','搜索','道具图鉴','加载中','道具指引'];
  for (let i = 0; i < positions.length; i++) {
    const { name, level } = positions[i];
    if (name.length < 2 || name.length > 45 || skip.some(s => name.includes(s))) continue;
    const start = positions[i].index;
    const end = i + 1 < positions.length ? positions[i + 1].index : text.length;
    let block = text.substring(start, end);
    let desc = block.replace(/^[\s\S]*?(?:价格|负债)[：:]\s*[\d]+\s*(?:金币)?\s*\n+/, '')
      .replace(/^[\s\S]*?购买后[^\n]*\n+/, '').replace(/\n+/g, ' ').trim();
    desc = desc.replace(/皖ICP[^\s]*|京公网[^\s]*|浅色模式[^\s]*|切换深色[^\s]*|保持浅色[^\s]*|不再提示/g, '').trim();
    if (desc.length > 350) desc = desc.substring(0, 350) + '...';
    const cat = inferCategory(name, desc);
    items.push({
      name,
      level: level === '未知' ? null : parseInt(level, 10),
      category: cat,
      description: desc || null
    });
  }
  return items;
}

function parseHeroesFromText(text) {
  const heroes = [];
  const matches = text.matchAll(/([\u4e00-\u9fa5]{2,8})\s*(\d+)\s*种玩法/g);
  const seen = new Set();
  for (const m of matches) {
    const name = m[1].trim();
    if (!seen.has(name) && !['英雄攻略','所有英雄'].includes(name)) {
      seen.add(name);
      heroes.push({ name, playCount: parseInt(m[2], 10) });
    }
  }
  return heroes;
}

function extractRules(text) {
  const rules = { trigger: [], damage: [], economy: [], exception: [] };
  const lines = text.split(/\n/);
  const all = text;

  const patterns = [
    { re: /结算效果?[^\n]{0,100}触发/g, group: 'trigger' },
    { re: /战备效果?[^\n]{0,100}触发/g, group: 'trigger' },
    { re: /摧毁效果?[^\n]{0,100}触发/g, group: 'trigger' },
    { re: /(?:获得时|购买后|主动使用)[^\n]{0,80}/g, group: 'trigger' },
    { re: /(?:每回合|每轮|每关|每16秒)[^\n]{0,80}/g, group: 'trigger' },
    { re: /攻击特效[^\n]{0,80}/g, group: 'damage' },
    { re: /(?:魔法伤害|物理伤害|特效伤害|范围伤害)[^\n]{0,60}/g, group: 'damage' },
    { re: /(?:标有负债|蓝港集团|每回合.*偿还|负债)[^\n]{0,100}/g, group: 'economy' },
    { re: /(?:价格|金币|黄金|刷新市场|偿还)[^\n]{0,60}/g, group: 'economy' },
    { re: /(?:无法|不会|不叠加|不继承|除非|除外|例外)[^\n]{0,80}/g, group: 'exception' },
    { re: /(?:可组装|可被填入)[^\n]{0,60}/g, group: 'exception' },
    { re: /(?:硬币特性|转动齿轮)[^\n]{0,80}/g, group: 'trigger' },
    { re: /(?:战旗道具|激励效果)[^\n]{0,80}/g, group: 'trigger' },
    { re: /(?:腐化值|邪能道具)[^\n]{0,80}/g, group: 'exception' },
    { re: /(?:自动道具|自动攻击)[^\n]{0,80}/g, group: 'trigger' }
  ];

  for (const { re, group } of patterns) {
    let m;
    while ((m = re.exec(all)) !== null) {
      const s = m[0].trim();
      if (s.length > 8 && s.length < 250 && !rules[group].includes(s)) {
        rules[group].push(s);
      }
    }
  }
  return rules;
}

async function run() {
  const result = {
    apis: [],
    heroes: [],
    items: [],
    rules: { trigger: [], damage: [], economy: [], exception: [] },
    limitations: []
  };

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      viewport: { width: 1920, height: 1080 }
    });
    const page = await context.newPage();
    page.setDefaultTimeout(25000);

    const apiCandidates = [];
    page.on('request', req => {
      const url = req.url();
      const type = req.resourceType();
      if (type !== 'xhr' && type !== 'fetch') return;
      try {
        const host = new URL(url).hostname;
        if (host.includes('rouge.wiki') && !host.includes('google')) {
          apiCandidates.push({ url, method: req.method() });
        }
      } catch (_) {}
    });

    await page.goto('https://www.rouge.wiki/#/home', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(1500);
    const heroLink = await page.$('text=英雄攻略');
    if (heroLink) await heroLink.click();
    await page.waitForTimeout(2500);
    const heroText = await page.evaluate(() => document.body.innerText);
    result.heroes = parseHeroesFromText(heroText);

    await page.goto('https://www.rouge.wiki/#/home', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(500);
    const itemLink = await page.$('text=图鉴');
    if (itemLink) await itemLink.click();
    await page.waitForTimeout(2500);
    for (let i = 0; i < 20; i++) {
      await page.evaluate(() => window.scrollBy(0, 600));
      await page.waitForTimeout(300);
    }
    const itemText = await page.evaluate(() => document.body.innerText);

    const categories = ['全部','齿轮','充能','摧毁','火花','结算','蓝港','灵魂','泰坦','硬币','战旗','咒文','邪能','自动','中立','毒蛇大师小玩意','合成道具','其他','诅咒道具','魔戒道具','传火'];
    result.items = parseItemsFromText(itemText);
    result.items.forEach(it => {
      if (!it.category) it.category = inferCategory(it.name, it.description);
    });

    result.rules = extractRules(itemText + '\n' + heroText);
    result.rules.economy = result.rules.economy.filter(r => !/^价格[：:]\s*\d+\s*金币$/.test(r));

    const seen = new Set();
    for (const a of apiCandidates) {
      const k = a.url + a.method;
      if (!seen.has(k)) {
        seen.add(k);
        result.apis.push({
          url: a.url,
          method: a.method,
          directAccess: 'not_tested'
        });
      }
    }
    if (result.apis.length === 0) {
      result.apis.push({
        url: 'N/A',
        method: 'N/A',
        directAccess: 'no',
        note: 'No rouge.wiki XHR/fetch found; data likely bundled in JS'
      });
    }

    for (const api of result.apis) {
      if (api.url.startsWith('https://api.rouge.wiki/')) {
        try {
          const resp = await page.request.get(api.url, { timeout: 10000 });
          const ok = resp.ok();
          const text = await resp.text();
          api.directAccess = ok && (text.startsWith('{') || text.startsWith('[')) ? 'yes' : 'no';
          if (api.directAccess === 'no') api.reason = 'status ' + resp.status();
        } catch (e) {
          api.directAccess = 'no';
          api.reason = e.message;
        }
      }
    }

    result.itemCategories = categories;

    try {
      const tagsResp = await page.request.get('https://api.rouge.wiki/api/tags', { timeout: 5000 });
      if (tagsResp.ok()) {
        const tagsData = JSON.parse(await tagsResp.text());
        result.heroTags = tagsData.data || [];
      }
    } catch (_) {}

    if (result.items.length < 100) {
      result.limitations.push(`Items extracted: ${result.items.length}, target 100+`);
    }
    result.limitations.push('Item categories inferred from name/description; not from API');

  } catch (e) {
    result.limitations.push('Error: ' + e.message);
  } finally {
    if (browser) await browser.close();
  }

  return result;
}

run().then(r => {
  const out = JSON.stringify(r, null, 2);
  fs.writeFileSync('rouge-wiki-data.json', out, 'utf8');
  console.log(out);
}).catch(e => console.error(e));
