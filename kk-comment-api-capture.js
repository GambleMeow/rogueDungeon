/**
 * 抓取 comment-api 帖子评论列表接口
 * 1) 打开 fab/180750
 * 2) 进入社区攻略，点击攻略帖
 * 3) 打开评论区并滚动，捕获 comment-api 请求
 */
const { chromium } = require('playwright');
const fs = require('fs');

async function run() {
  const result = {
    commentApis: [],
    directAccess: [],
    blockers: [],
    domHints: [],
    summary: ''
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

    const commentApiCalls = [];

    page.on('response', async res => {
      const url = res.url();
      if (!url.includes('comment-api') && !url.includes('platform-comment-api')) return;

      const method = res.request().method();
      const status = res.status();
      const req = res.request();
      const postData = req.postData ? req.postData() : null;

      let body = '';
      try { body = await res.text(); } catch (_) {}

      let sample = null;
      if (body && (body.startsWith('{') || body.startsWith('['))) {
        try {
          const j = JSON.parse(body);
          if (j && typeof j === 'object') {
            sample = { status: j.status };
            if (j.data) {
              if (Array.isArray(j.data)) sample.data = `[${j.data.length} items]`;
              else if (typeof j.data === 'object') sample.data = Object.keys(j.data).slice(0, 12);
              else sample.data = j.data;
            }
          }
        } catch (_) {}
      }

      commentApiCalls.push({
        url,
        method,
        status,
        postData,
        sample,
        bodySample: body ? body.substring(0, 3000) : null
      });
    });

    await page.goto('https://www.kkdzpt.com/fab/180750', { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(2500);

    // 获取可点击的帖子链接
    const links = await page.evaluate(() => {
      const as = Array.from(document.querySelectorAll('a[href]'));
      return as.map(a => ({ href: a.href, text: a.textContent?.trim().substring(0, 50) }))
        .filter(x => x.text && (x.text.includes('攻略') || x.text.includes('BOSS') || x.text.includes('详细') || x.href.includes('topic')));
    });
    result.domHints.push({ foundLinks: links.slice(0, 15) });

    // 2) 点击「社区攻略」tab
    const tabSelectors = ['text=社区攻略', 'a:has-text("社区攻略")', 'div:has-text("社区攻略")', '[class*="tab"]:has-text("社区攻略")'];
    for (const sel of tabSelectors) {
      try {
        const el = await page.$(sel);
        if (el) {
          await el.click();
          await page.waitForTimeout(3000);
          break;
        }
      } catch (_) {}
    }

    // 点击攻略帖：优先含「详细攻略」「BOSS图鉴」的（使用模糊匹配）
    const postSelectors = [
      'a:has-text("详细攻略")',
      'a:has-text("BOSS图鉴")',
      'a:has-text("肉鸽地牢详细攻略")',
      'a:has-text("游戏崩图")',
      'a:has-text("BUG")',
      '[class*="topic"]:has-text("攻略")',
      '[class*="item"]:has-text("攻略")',
      'div[class*="topic"] >> a',
      'li >> a',
      'a[href*="topic"]'
    ];
    let postClicked = false;
    for (const sel of postSelectors) {
      try {
        const el = await page.$(sel);
        if (el) {
          await el.click();
          postClicked = true;
          await page.waitForTimeout(4000);
          break;
        }
      } catch (_) {}
    }
    if (!postClicked) {
      const allClickables = await page.$$('a, [role="button"], [class*="topic"], [class*="post"], [class*="item"]');
      for (const el of allClickables.slice(0, 30)) {
        try {
          const text = await el.textContent();
          if (text && (text.includes('攻略') || text.includes('BOSS') || text.includes('详细') || text.includes('肉鸽'))) {
            await el.click();
            postClicked = true;
            await page.waitForTimeout(4000);
            break;
          }
        } catch (_) {}
      }
    }
    if (!postClicked) result.blockers.push('无法点击进入帖子详情');

    // 评论区滚动
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(2500);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(2500);

    // 去重并提取
    const seen = new Map();
    for (const c of commentApiCalls) {
      const base = c.url.split('?')[0];
      if (seen.has(base)) continue;
      seen.set(base, true);

      const u = new URL(c.url);
      const params = {};
      u.searchParams.forEach((v, k) => params[k] = v);

      result.commentApis.push({
        url: c.url,
        method: c.method,
        status: c.status,
        params: Object.keys(params).length ? params : null,
        postData: c.postData,
        sample: c.sample,
        bodySample: c.bodySample ? c.bodySample.substring(0, 2000) : null
      });
    }

    // 5) 探测评论接口（含 gateway）
    const topicId = '65151b52cdddb63ebc890efc';
    const probes = [
      `https://comment-api.kkdzpt.com/api/v1/topic/comments?mapId=180750&topicId=${topicId}&start=0&limit=10`,
      `https://comment-api.kkdzpt.com/api/v1/comment/list?mapId=180750&topicId=${topicId}&start=0&limit=10`,
      `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/topic/comments?mapId=180750&topicId=${topicId}&start=0&limit=10`,
      `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/comment/reply_list?mapId=180750&topicId=${topicId}&start=0&limit=10`,
      `https://kk-web-gateway.kkdzpt.com/platform-comment-api/api/v1/topic/replies?mapId=180750&topicId=${topicId}&start=0&limit=10`
    ];
    for (const u of probes) {
      try {
        const resp = await page.request.get(u, { timeout: 10000 });
        const text = await resp.text();
        let sample = null;
        if (text && text.startsWith('{')) {
          try {
            const j = JSON.parse(text);
            sample = { status: j.status };
            if (j.data) {
              if (Array.isArray(j.data)) {
                sample.dataType = 'array';
                sample.length = j.data.length;
                if (j.data[0]) sample.firstItemKeys = Object.keys(j.data[0]);
              } else sample.dataKeys = Object.keys(j.data);
            }
            if (j.message) sample.message = j.message;
          } catch (_) {}
        }
        result.directAccess.push({ url: u, status: resp.status(), sample });
      } catch (e) {
        result.directAccess.push({ url: u, error: e.message });
      }
    }

    // 6) 在页面上下文中 fetch（带 cookie）尝试评论接口
    try {
      const inPageFetch = await page.evaluate(async (topicId) => {
        const url = `https://comment-api.kkdzpt.com/api/v1/topic/comments?mapId=180750&topicId=${topicId}&start=0&limit=10`;
        const r = await fetch(url, { credentials: 'include' });
        const j = await r.json();
        return { status: r.status, data: j.data ? (Array.isArray(j.data) ? j.data.length : Object.keys(j.data)) : null, message: j.message };
      }, topicId);
      result.inPageFetch = inPageFetch;
    } catch (e) {
      result.inPageFetchError = e.message;
    }

  } catch (e) {
    result.error = e.message;
  } finally {
    if (browser) await browser.close();
  }

  return result;
}

run().then(r => {
  fs.writeFileSync('kk-comment-result.json', JSON.stringify(r, null, 2), 'utf8');
  console.log(JSON.stringify(r, null, 2));
}).catch(e => console.error(e));
