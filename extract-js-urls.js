/**
 * 提取 rouge.wiki 页面加载的所有 JS 脚本 URL
 */
const { chromium } = require('playwright');
const fs = require('fs');

async function run() {
  const result = {
    scriptUrls: [],
    byType: { main: [], app: [], chunk: [], vendor: [], other: [] },
    toolboxCandidates: [],
    directAccess: []
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

    const scriptUrls = new Set();
    const scriptDetails = [];

    page.on('response', async res => {
      const url = res.url();
      const type = res.request().resourceType();
      if (type === 'script') {
        scriptUrls.add(url);
        try {
          const headers = res.headers();
          const cl = headers['content-length'] || '';
          scriptDetails.push({
            url,
            contentLength: cl ? parseInt(cl, 10) : null
          });
        } catch (_) {}
      }
    });

    await page.goto('https://www.rouge.wiki/#/home', { waitUntil: 'networkidle', timeout: 45000 });
    await page.waitForTimeout(2000);

    const toolbox = await page.$('text=工具箱');
    if (toolbox) {
      await toolbox.click();
      await page.waitForTimeout(1500);
      for (const t of ['熔核收益计算', '战车模块概率', '敌方面板查询', '经济计算']) {
        const link = await page.$(`text=${t}`);
        if (link) { await link.click(); await page.waitForTimeout(1200); }
      }
    }
    await page.goto('https://www.rouge.wiki/#/hero', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(1500);
    await page.goto('https://www.rouge.wiki/#/item', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(1500);

    const urls = [...scriptUrls];
    result.scriptUrls = urls;

    for (const url of urls) {
      const lower = url.toLowerCase();
      if (lower.includes('main') || lower.includes('index')) result.byType.main.push(url);
      else if (lower.includes('app')) result.byType.app.push(url);
      else if (lower.includes('chunk')) result.byType.chunk.push(url);
      else if (lower.includes('vendor') || lower.includes('runtime')) result.byType.vendor.push(url);
      else result.byType.other.push(url);
    }

    const rougeUrls = urls.filter(u => u.includes('rouge.wiki'));
    const toolboxKeywords = ['tool', 'calc', 'Tool', 'Calc', 'Toolbox', '熔核', '战车', '经济', '敌人', 'module', 'economy', 'enemy'];
    for (const url of rougeUrls) {
      const lower = url.toLowerCase();
      const name = url.split('/').pop().split('?')[0];
      if (toolboxKeywords.some(k => lower.includes(k) || name.includes(k))) {
        result.toolboxCandidates.push({ url, reason: 'filename match' });
      }
    }

    for (const url of urls) {
      try {
        const resp = await page.request.get(url, { timeout: 10000 });
        const status = resp.status();
        const ct = resp.headers()['content-type'] || '';
        const text = await resp.text();
        const size = text ? text.length : 0;
        result.directAccess.push({
          url,
          status,
          contentType: ct,
          size,
          accessible: status === 200
        });
      } catch (e) {
        result.directAccess.push({ url, error: e.message, accessible: false });
      }
    }

    const sizes = {};
    for (const d of result.directAccess) {
      if (d.url.includes('rouge.wiki') && d.size) sizes[d.url] = d.size;
    }
    const sorted = Object.entries(sizes).sort((a, b) => b[1] - a[1]);
    for (let i = 0; i < Math.min(5, sorted.length); i++) {
      if (sorted[i][1] > 10000) {
        result.toolboxCandidates.push({ url: sorted[i][0], reason: `large bundle (${sorted[i][1]} bytes), likely contains app/toolbox logic` });
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
  fs.writeFileSync('js-urls-result.json', out, 'utf8');
  console.log(out);
}).catch(e => console.error(e));
