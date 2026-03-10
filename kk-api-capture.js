/**
 * KK对战平台 地图详情页 API 抓取
 * https://www.kkdzpt.com/fab/180750
 */
const { chromium } = require('playwright');
const fs = require('fs');

async function run() {
  const result = {
    apis: [],
    directAccess: [],
    nextData: null,
    conclusions: []
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

    const apiCalls = [];

    page.on('response', async res => {
      const url = res.url();
      const method = res.request().method();
      const status = res.status();
      const type = res.request().resourceType();
      if (type !== 'xhr' && type !== 'fetch') return;
      if (url.includes('gtag') || url.includes('google') || url.includes('track/')) return;

      const ct = res.headers()['content-type'] || '';
      let body = '';
      try { body = await res.text(); } catch (_) {}

      let topFields = [];
      let sample = null;
      if (body && (body.startsWith('{') || body.startsWith('['))) {
        try {
          const j = JSON.parse(body);
          topFields = Array.isArray(j) ? ['[array]'] : Object.keys(j);
          if (typeof j === 'object' && j !== null && !Array.isArray(j)) {
            sample = {};
            for (const k of topFields.slice(0, 12)) {
              const v = j[k];
              if (Array.isArray(v)) sample[k] = `[${v.length} items]`;
              else if (typeof v === 'object' && v) sample[k] = '{...}';
              else sample[k] = typeof v === 'string' && v.length > 80 ? v.substring(0, 80) + '...' : v;
            }
          }
        } catch (_) {}
      }

      apiCalls.push({
        url,
        method,
        status,
        contentType: ct,
        topFields,
        sample,
        bodySample: body ? body.substring(0, 1500) : null
      });
    });

    await page.goto('https://www.kkdzpt.com/fab/180750', { waitUntil: 'networkidle', timeout: 45000 });
    await page.waitForTimeout(2000);

    const html = await page.content();
    const nextMatch = html.match(/<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/);
    if (nextMatch) {
      try {
        result.nextData = JSON.parse(nextMatch[1]);
      } catch (_) {}
    }

    const tabLabels = ['评论', '社区攻略', '如何游戏', '地图说明'];
    for (const label of tabLabels) {
      try {
        const tab = await page.$(`text=${label}`);
        if (tab) {
          await tab.click();
          await page.waitForTimeout(2000);
        }
      } catch (_) {}
    }

    const seen = new Map();
    for (const a of apiCalls) {
      const key = a.url + '|' + a.method;
      if (!seen.has(key)) {
        seen.set(key, true);
        result.apis.push({
          url: a.url,
          method: a.method,
          status: a.status,
          contentType: a.contentType,
          topFields: a.topFields,
          sample: a.sample
        });
      }
    }

    const kkUrls = result.apis.filter(a => a.url.includes('kkdzpt.com')).map(a => a.url);
    const uniqueUrls = [...new Set(kkUrls)];

    for (const url of uniqueUrls) {
      if (!url.includes('/api/') && !url.includes('fab') && !url.includes('detail')) continue;
      try {
        const resp = await page.request.get(url, { timeout: 10000 });
        const text = await resp.text();
        const ct = resp.headers()['content-type'] || '';
        let topFields = [];
        let sample = null;
        if (text && (text.startsWith('{') || text.startsWith('['))) {
          try {
            const j = JSON.parse(text);
            topFields = Array.isArray(j) ? ['[array]'] : Object.keys(j);
            if (typeof j === 'object' && j !== null && !Array.isArray(j)) {
              sample = {};
              for (const k of topFields.slice(0, 15)) {
                const v = j[k];
                if (Array.isArray(v)) sample[k] = v.length > 0 ? (typeof v[0] === 'object' ? `[${v.length} items, keys: ${Object.keys(v[0] || {}).join(',')}]` : `[${v.length} items]`) : '[]';
                else if (typeof v === 'object' && v) sample[k] = `{${Object.keys(v).slice(0, 5).join(',')}...}`;
                else sample[k] = typeof v === 'string' && v.length > 100 ? v.substring(0, 100) + '...' : v;
              }
            }
          } catch (_) {}
        }
        result.directAccess.push({
          url,
          method: 'GET',
          status: resp.status(),
          contentType: ct,
          topFields,
          sample
        });
      } catch (e) {
        result.directAccess.push({ url, error: e.message });
      }
    }

    const commonPaths = [
      'https://www.kkdzpt.com/api/map/detail/180750',
      'https://api.kkdzpt.com/map/180750',
      'https://www.kkdzpt.com/api/fab/180750',
      'https://www.kkdzpt.com/api/map/180750/detail',
      'https://comment-api.kkdzpt.com/api/v1/topic/count?mapId=180750',
      'https://comment-api.kkdzpt.com/api/v1/topic/list?mapId=180750',
      'https://comment-api.kkdzpt.com/api/v1/topic/detail?mapId=180750',
      'https://www.kkdzpt.com/api/fab/180750/detail'
    ];
    for (const u of commonPaths) {
      if (result.directAccess.some(d => d.url === u && !d.error)) continue;
      try {
        const resp = await page.request.get(u, { timeout: 8000 });
        const text = await resp.text();
        let sample = null;
        if (text && text.startsWith('{')) {
          try {
            const j = JSON.parse(text);
            sample = {};
            for (const k of Object.keys(j).slice(0, 15)) {
              const v = j[k];
              sample[k] = Array.isArray(v) ? `[${v.length}]` : (typeof v === 'string' && v.length > 80 ? v.substring(0, 80) + '...' : v);
            }
          } catch (_) {}
        }
        result.directAccess.push({
          url: u,
          status: resp.status(),
          contentType: resp.headers()['content-type'] || '',
          sample
        });
      } catch (e) {
        result.directAccess.push({ url: u, error: e.message });
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
  fs.writeFileSync('kk-api-result.json', out, 'utf8');
  console.log(out);
}).catch(e => console.error(e));
