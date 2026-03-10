/**
 * rouge.wiki 工具箱页面提取
 * 熔核收益计算、战车模块概率、敌方面板查询、经济计算、账单公示
 */
const { chromium } = require('playwright');
const fs = require('fs');

const TOOL_LINKS = [
  '熔核收益计算',
  '战车模块概率',
  '敌方面板查询',
  '经济计算',
  '账单公示'
];

async function run() {
  const result = {
    tools: [],
    apis: [],
    formulasExposed: [],
    godotValue: []
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
      try {
        const host = new URL(url).hostname;
        if (host.includes('rouge.wiki') && !host.includes('google')) {
          const ct = res.headers()['content-type'] || '';
          if (ct.includes('json') || url.includes('/api/')) {
            let body = '';
            try { body = await res.text(); } catch (_) {}
            apiCalls.push({ url, method: res.request().method(), status: res.status(), body: body?.substring(0, 3000) });
          }
        }
      } catch (_) {}
    });

    await page.goto('https://www.rouge.wiki/#/home', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(2000);

    const toolbox = await page.$('text=工具箱');
    if (toolbox) await toolbox.click();
    await page.waitForTimeout(1500);

    for (const toolName of TOOL_LINKS) {
      const tool = { name: toolName, accessible: false, inputs: [], outputs: [], defaults: {}, descriptions: [], formulas: [], apiUsed: null };
      try {
        const link = await page.$(`text=${toolName}`);
        if (!link) {
          tool.accessible = false;
          tool.note = 'Link not found';
          result.tools.push(tool);
          continue;
        }
        await link.click();
        await page.waitForTimeout(2500);

        const text = await page.evaluate(() => document.body.innerText);
        const html = await page.evaluate(() => document.body.innerHTML);

        tool.accessible = true;
        tool.fullText = text.substring(0, 5000);

        const inputs = await page.$$eval('input, select, [type="number"], [type="text"], [role="spinbutton"]', els =>
          els.map(e => ({
            name: e.name || e.placeholder || e.getAttribute('aria-label') || e.id,
            type: e.type,
            value: e.value,
            placeholder: e.placeholder,
            min: e.min,
            max: e.max,
            step: e.step
          }))
        );
        tool.inputs = inputs.filter(i => i.name);

        const labels = await page.$$eval('label, .el-form-item__label, [class*="label"]', els =>
          els.map(e => e.textContent?.trim()).filter(Boolean)
        );
        tool.labels = labels.slice(0, 30);

        const outputs = await page.$$eval('[class*="result"], [class*="output"], [class*="value"], .el-input__inner readonly', els =>
          els.map(e => ({ text: e.textContent?.trim(), tag: e.tagName })).filter(x => x.text?.length > 0 && x.text.length < 200)
        );
        tool.outputs = outputs;

        const formulaMatches = text.match(/\d+[%×*+\-\/]\d+|概率|刷新|成本|收益|公式|=\s*[\d.]+|[\d.]+%\s*[×*]|权重|期望|利息|偿还|负债|波数|经济/g) || [];
        tool.formulas = [...new Set(formulaMatches)];

        const defaults = {};
        await page.$$eval('input[type="number"], input[type="text"]', els => {
          els.forEach(e => {
            if (e.value && e.name && !e.name.includes('theme')) defaults[e.placeholder || e.name] = e.value;
          });
          return els.map(e => ({ name: e.placeholder || e.name, value: e.value })).filter(x => x.value && !x.name?.includes('theme'));
        }).then(arr => { tool.defaults = Object.fromEntries(arr.map(x => [x.name, x.value])); }).catch(() => {});

        const descMatches = text.match(/[^\n]{10,120}(?:说明|描述|计算|公式|概率|收益)[^\n]{0,80}/g) || [];
        tool.descriptions = descMatches.slice(0, 15);

        if (apiCalls.length > 0) {
          tool.apiUsed = apiCalls[apiCalls.length - 1];
        }

        result.tools.push(tool);
      } catch (e) {
        tool.error = e.message;
        result.tools.push(tool);
      }
    }

    result.apis = apiCalls;

    const allFormulas = new Set();
    result.tools.forEach(t => (t.formulas || []).forEach(f => allFormulas.add(f)));
    result.formulasExposed = [...allFormulas];

    result.godotValue = [
      '输入输出结构可直接映射为Godot UI节点与信号',
      '公式/参数可复刻核心数值逻辑',
      'API接口可作数据校验或热更新来源'
    ];

  } catch (e) {
    result.error = e.message;
  } finally {
    if (browser) await browser.close();
  }

  return result;
}

run().then(r => {
  const out = JSON.stringify(r, null, 2);
  fs.writeFileSync('toolbox-extract.json', out, 'utf8');
  console.log(out);
}).catch(e => console.error(e));
