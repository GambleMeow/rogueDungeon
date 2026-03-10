/**
 * rouge.wiki API 挖掘 - 全程记录 network 请求
 * 1) 五页面记录 XHR/fetch/doc，筛选 api.rouge.wiki
 * 2) 返回 url/method/status/content-type/顶层字段
 * 3) 直接访问提取核心字段
 * 4) 验证 敌人/波次/boss/经济/模块概率 接口
 * 5) 禁用缓存 + hard reload
 */
const { chromium } = require('playwright');
const fs = require('fs');

const PAGES = [
  { name: '首页', url: 'https://www.rouge.wiki/#/home' },
  { name: '英雄攻略', url: 'https://www.rouge.wiki/#/home', click: '英雄攻略' },
  { name: '图鉴', url: 'https://www.rouge.wiki/#/home', click: '图鉴' },
  { name: '工具箱', url: 'https://www.rouge.wiki/#/home', click: '工具箱' }
];

async function run() {
  const result = {
    captured: [],
    directAccess: [],
    byCategory: { enemy: [], wave: [], boss: [], economy: [], moduleProb: [] },
    conclusions: { available: [], missing: [] }
  };

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      viewport: { width: 1920, height: 1080 },
      ignoreHTTPSErrors: true
    });

    await context.route('**/*', route => route.continue());

    const page = await context.newPage();
    page.setDefaultTimeout(30000);

    const apiCalls = new Map();
    const captureResponse = async (res) => {
      const url = res.url();
      try {
        const u = new URL(url);
        if (!u.hostname.includes('api.rouge.wiki')) return;
        const key = url + '|' + res.request().method();
        if (apiCalls.has(key)) return;
        const headers = res.headers();
        const ct = headers['content-type'] || '';
        let body = '';
        try { body = await res.text(); } catch (_) {}
        let topFields = [];
        if (body && (body.startsWith('{') || body.startsWith('['))) {
          try {
            const j = JSON.parse(body);
            topFields = Array.isArray(j) ? ['[array]'] : Object.keys(j);
          } catch (_) {}
        }
        apiCalls.set(key, {
          url,
          method: res.request().method(),
          status: res.status(),
          contentType: ct,
          topFields,
          bodySample: body ? body.substring(0, 500) : null
        });
      } catch (_) {}
    };

    page.on('response', captureResponse);

    const ts = Date.now();
    for (const p of PAGES) {
      await page.goto(`https://www.rouge.wiki/?_=${ts}#/home`, { waitUntil: 'networkidle', timeout: 45000 });
      await page.waitForTimeout(1500);
      if (p.click) {
        const el = await page.$(`text=${p.click}`);
        if (el) {
          await el.click();
          await page.waitForTimeout(2000);
        }
      }
      if (p.name === '工具箱') {
        const toolbox = await page.$('text=工具箱');
        if (toolbox) await toolbox.click();
        await page.waitForTimeout(800);
        const toolLinks = ['熔核收益计算', '战车模块概率', '敌方面板查询', '经济计算'];
        for (const t of toolLinks) {
          const link = await page.$(`text=${t}`);
          if (link) {
            await link.click();
            await page.waitForTimeout(1500);
          }
        }
      }
    }

    result.captured = [...apiCalls.values()];

    if (result.captured.length === 0) {
      await page.goto('https://www.rouge.wiki/', { waitUntil: 'networkidle', timeout: 45000 });
      await page.evaluate(() => location.reload(true));
      await page.waitForTimeout(3000);
      await page.goto('https://www.rouge.wiki/#/hero', { waitUntil: 'networkidle', timeout: 45000 });
      await page.waitForTimeout(2000);
      await page.goto('https://www.rouge.wiki/#/item', { waitUntil: 'networkidle', timeout: 45000 });
      await page.waitForTimeout(2000);
      result.captured = [...apiCalls.values()];
    }

    const uniqueUrls = [...new Set(result.captured.map(c => c.url))];
    for (const url of uniqueUrls) {
      try {
        const resp = await page.request.get(url, { timeout: 10000 });
        const ct = resp.headers()['content-type'] || '';
        const text = await resp.text();
        let topFields = [];
        let coreSample = null;
        if (text && (text.startsWith('{') || text.startsWith('['))) {
          try {
            const j = JSON.parse(text);
            topFields = Array.isArray(j) ? ['[array]'] : Object.keys(j);
            if (typeof j === 'object' && j !== null) {
              const sample = {};
              for (const k of topFields.slice(0, 5)) {
                const v = j[k];
                if (Array.isArray(v)) sample[k] = `[${v.length} items]`;
                else if (typeof v === 'object') sample[k] = v ? '{...}' : null;
                else sample[k] = typeof v === 'string' && v.length > 50 ? v.substring(0, 50) + '...' : v;
              }
              coreSample = sample;
            }
          } catch (_) {}
        }
        result.directAccess.push({
          url,
          method: 'GET',
          status: resp.status(),
          contentType: ct,
          topFields,
          coreSample
        });
      } catch (e) {
        result.directAccess.push({ url, error: e.message });
      }
    }

    const allText = JSON.stringify(result.captured) + JSON.stringify(result.directAccess);
    const keywords = [
      { key: 'enemy', terms: ['敌人', 'enemy', 'unit', '单位'] },
      { key: 'wave', terms: ['波次', 'wave', 'round'] },
      { key: 'boss', terms: ['boss', 'BOSS'] },
      { key: 'economy', terms: ['经济', 'economy', 'gold', '金币'] },
      { key: 'moduleProb', terms: ['模块', '概率', 'module', 'probability'] }
    ];
    for (const { key, terms } of keywords) {
      for (const c of result.captured) {
        if (terms.some(t => c.url.toLowerCase().includes(t) || (c.bodySample || '').toLowerCase().includes(t))) {
          result.byCategory[key].push(c.url);
        }
      }
      for (const d of result.directAccess) {
        if (d.coreSample && terms.some(t => JSON.stringify(d.coreSample).toLowerCase().includes(t))) {
          result.byCategory[key].push(d.url);
        }
      }
      result.byCategory[key] = [...new Set(result.byCategory[key])];
    }

    const knownApis = ['https://api.rouge.wiki/api/game/static-data', 'https://api.rouge.wiki/api/tags'];
    for (const u of knownApis) {
      if (!result.directAccess.some(d => d.url === u)) {
        try {
          const resp = await page.request.get(u, { timeout: 15000 });
          const text = await resp.text();
          let topFields = [];
          let coreSample = null;
          let staticDataStructure = null;
          if (text && text.startsWith('{')) {
            try {
              const j = JSON.parse(text);
              topFields = Object.keys(j);
              coreSample = {};
              for (const k of topFields.slice(0, 8)) {
                const v = j[k];
                if (Array.isArray(v)) coreSample[k] = `[${v.length} items]`;
                else if (typeof v === 'object' && v) coreSample[k] = `{${Object.keys(v).slice(0, 5).join(',')}...}`;
                else coreSample[k] = typeof v === 'string' && v.length > 50 ? v.substring(0, 50) + '...' : v;
              }
              if (u.includes('static-data') && j.data) {
                const d = j.data;
                staticDataStructure = {
                  keys: Object.keys(d),
                  sample: {}
                };
                for (const k of Object.keys(d).slice(0, 15)) {
                  const v = d[k];
                  if (Array.isArray(v)) {
                    staticDataStructure.sample[k] = v.length > 0 ? { count: v.length, firstKeys: Object.keys(v[0] || {}).slice(0, 5) } : [];
                  } else if (typeof v === 'object') {
                    staticDataStructure.sample[k] = Object.keys(v || {}).slice(0, 5);
                  }
                }
              }
            } catch (_) {}
          }
          result.directAccess.push({
            url: u,
            method: 'GET',
            status: resp.status(),
            contentType: resp.headers()['content-type'] || '',
            topFields,
            coreSample,
            staticDataStructure
          });
        } catch (e) {
          result.directAccess.push({ url: u, error: e.message });
        }
      }
    }

    result.conclusions.available = result.directAccess
      .filter(d => d.status === 200 && d.topFields?.length)
      .map(d => ({ url: d.url, fields: d.topFields }));

    const needed = ['敌人/单位', '波次', 'boss', '经济', '模块概率'];
    for (const n of needed) {
      const found = result.byCategory.enemy.length || result.byCategory.wave.length ||
        result.byCategory.boss.length || result.byCategory.economy.length || result.byCategory.moduleProb.length;
      if (!result.directAccess.some(d => d.url && d.coreSample && (
        (n.includes('敌人') && JSON.stringify(d.coreSample).includes('unit')) ||
        (n.includes('波次') && JSON.stringify(d.coreSample).includes('wave')) ||
        (n.includes('boss') && JSON.stringify(d.coreSample).toLowerCase().includes('boss')) ||
        (n.includes('经济') && JSON.stringify(d.coreSample).includes('gold')) ||
        (n.includes('模块') && JSON.stringify(d.coreSample).includes('module'))
      ))) {
        result.conclusions.missing.push(n);
      }
    }

  } catch (e) {
    result.error = e.message;
  } finally {
    if (browser) await browser.close();
  }

  return result;
}

run().then(r => {
  const out = JSON.stringify(r, null, 2);
  fs.writeFileSync('api-discovery-result.json', out, 'utf8');
  console.log(out);
}).catch(e => console.error(e));
