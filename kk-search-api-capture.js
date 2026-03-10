/**
 * 社区攻略区域：搜索框/筛选功能 + 抓取 search/query 相关 API
 */
const { chromium } = require('playwright');
const fs = require('fs');

async function run() {
  const result = {
    hasSearchUI: null,
    hasFilterUI: null,
    uiElements: [],
    searchApis: [],
    allCommunityApis: [],
    directProbes: [],
    blockers: []
  };

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      viewport: { width: 1920, height: 1080 }
    });
    const page = await context.newPage();
    page.setDefaultTimeout(20000);

    const apiCalls = [];

    page.on('response', async res => {
      const url = res.url();
      const method = res.request().method();
      const status = res.status();
      const type = res.request().resourceType();
      if (type !== 'xhr' && type !== 'fetch') return;
      if (url.includes('gtag') || url.includes('track/')) return;

      const isCommunity = url.includes('comment-api') || url.includes('platform-comment-api') || url.includes('topic') || url.includes('search') || url.includes('query');
      if (!isCommunity) return;

      let body = '';
      try { body = await res.text(); } catch (_) {}

      let sample = null;
      if (body && (body.startsWith('{') || body.startsWith('['))) {
        try {
          const j = JSON.parse(body);
          sample = { status: j.status };
          if (j.data) {
            if (Array.isArray(j.data)) sample.data = `[${j.data.length} items]`;
            else if (typeof j.data === 'object') sample.dataKeys = Object.keys(j.data).slice(0, 15);
            else sample.data = j.data;
          }
          if (j.message) sample.message = j.message;
        } catch (_) {}
      }

      apiCalls.push({
        url,
        method,
        status,
        sample,
        bodySample: body ? body.substring(0, 1500) : null
      });
    });

    await page.goto('https://www.kkdzpt.com/fab/180750', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(2500);

    // 点击「社区攻略」tab
    const tabEl = await page.$('text=社区攻略');
    if (tabEl) {
      await tabEl.click();
      await page.waitForTimeout(3500);
    } else {
      result.blockers.push('未找到社区攻略 tab');
    }

    // 检测搜索框、筛选、输入框
    const uiInfo = await page.evaluate(() => {
      const searchSelectors = ['input[type="search"]', 'input[placeholder*="搜索"]', 'input[placeholder*="查询"]', 'input[placeholder*="攻略"]', '[class*="search"] input', 'input[class*="search"]', '[aria-label*="search"]', '[role="searchbox"]'];
      const filterSelectors = ['[class*="filter"]', '[class*="select"]', 'select', '[class*="tab"]', '[class*="category"]', 'button:has-text("筛选")', 'button:has-text("分类")'];
      const found = [];
      for (const sel of searchSelectors) {
        try {
          const el = document.querySelector(sel);
          if (el) found.push({ type: 'search', selector: sel, placeholder: el.placeholder, visible: el.offsetParent !== null });
        } catch (_) {}
      }
      for (const sel of filterSelectors) {
        try {
          const els = document.querySelectorAll(sel);
          els.forEach((el, i) => {
            if (el && el.offsetParent && found.length < 20) {
              found.push({ type: 'filter', selector: sel, text: el.textContent?.trim().substring(0, 50) });
            }
          });
        } catch (_) {}
      }
      const allInputs = Array.from(document.querySelectorAll('input')).map(i => ({ type: i.type, placeholder: i.placeholder, name: i.name }));
      const allButtons = Array.from(document.querySelectorAll('button, [role="button"]')).slice(0, 15).map(b => ({ text: b.textContent?.trim().substring(0, 40) }));
      return { found, allInputs, allButtons };
    });
    result.uiElements = uiInfo;

    result.hasSearchUI = uiInfo.allInputs.some(i => (i.placeholder || '').includes('搜索') || (i.placeholder || '').includes('查询') || (i.placeholder || '').includes('攻略'));
    result.hasFilterUI = uiInfo.found.some(f => f.type === 'filter') || uiInfo.allButtons.some(b => (b.text || '').includes('筛选') || (b.text || '').includes('分类'));

    // 若有搜索框，输入关键词并触发
    if (result.hasSearchUI || uiInfo.allInputs.length > 0) {
      const searchInput = await page.$('input[type="search"], input[placeholder*="搜索"], input[placeholder*="查询"], input[placeholder*="攻略"]');
      if (searchInput) {
        await searchInput.fill('攻略');
        await page.waitForTimeout(2000);
        const searchBtn = await page.$('button[type="submit"], [class*="search"] button, button:has-text("搜索")');
        if (searchBtn) await searchBtn.click();
        await page.waitForTimeout(2500);
      } else {
        const firstInput = await page.$('input');
        if (firstInput) {
          await firstInput.fill('肉鸽');
          await page.waitForTimeout(1500);
          await page.keyboard.press('Enter');
          await page.waitForTimeout(2500);
        }
      }
    }

    // 尝试点击筛选/分类
    const filterBtn = await page.$('button:has-text("筛选"), button:has-text("分类"), [class*="filter"]');
    if (filterBtn) {
      await filterBtn.click();
      await page.waitForTimeout(2000);
    }

    // 去重 API
    const seen = new Map();
    for (const c of apiCalls) {
      const key = c.url;
      if (seen.has(key)) continue;
      seen.set(key, true);
      const u = new URL(c.url);
      const params = {};
      u.searchParams.forEach((v, k) => params[k] = v);

      const entry = {
        url: c.url,
        method: c.method,
        status: c.status,
        params: Object.keys(params).length ? params : null,
        sample: c.sample
      };
      result.allCommunityApis.push(entry);
      if (c.url.toLowerCase().includes('search') || c.url.toLowerCase().includes('query')) {
        result.searchApis.push(entry);
      }
    }

    // 直接探测常见搜索接口
    const searchProbes = [
      'https://comment-api.kkdzpt.com/api/v1/topic/search?mapId=180750&keyword=攻略&start=0&limit=10',
      'https://comment-api.kkdzpt.com/api/v1/topic/query?mapId=180750&keyword=攻略&start=0&limit=10',
      'https://comment-api.kkdzpt.com/api/v1/search/topic?mapId=180750&keyword=攻略',
      'https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/topic/search?mapId=180750&keyword=攻略&start=0&limit=10',
      'https://comment-api.kkdzpt.com/api/v1/topic/page_query_topics?mapId=180750&orderType=1&keyword=攻略&start=0&limit=10'
    ];
    for (const u of searchProbes) {
      try {
        const resp = await page.request.get(u, { timeout: 8000 });
        const text = await resp.text();
        let sample = null;
        if (text && text.startsWith('{')) {
          try {
            const j = JSON.parse(text);
            sample = { status: j.status, message: j.message };
            if (j.data) {
              if (Array.isArray(j.data)) sample.dataLength = j.data.length;
              else sample.dataKeys = Object.keys(j.data);
            }
          } catch (_) {}
        }
        result.directProbes.push({ url: u, status: resp.status(), sample });
      } catch (e) {
        result.directProbes.push({ url: u, error: e.message });
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
  fs.writeFileSync('kk-search-result.json', JSON.stringify(r, null, 2), 'utf8');
  console.log(JSON.stringify(r, null, 2));
}).catch(e => console.error(e));
