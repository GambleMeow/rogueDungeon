const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const OUTPUT_DIR = path.resolve(__dirname, "./cdp-output");
const USER_DATA_DIR = path.resolve(__dirname, "./cdp-profile");
const TARGET_URL = "https://www.doubao.com/chat/create-image";
const PROMPT_TEXT =
  "对于图片中的主体抽象出来，然后重新生成一个游戏风格的图片。";
const DEFAULT_IMAGE_PATH = path.resolve(__dirname, "../../icons/passives/PASBTNBash.png");

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}
if (!fs.existsSync(USER_DATA_DIR)) {
  fs.mkdirSync(USER_DATA_DIR, { recursive: true });
}

function nowTag() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function ensureParentDir(filePath) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

async function clickFirstVisible(page, selectors) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if ((await locator.count()) === 0) {
      continue;
    }
    const visible = await locator.isVisible().catch(() => false);
    if (!visible) {
      continue;
    }
    await locator.click({ timeout: 3000 }).catch(() => {});
    await page.waitForTimeout(500);
    return selector;
  }
  return null;
}

async function uploadReferenceImage(page, filePath) {
  let input = page.locator("input[type='file']");
  if ((await input.count()) > 0) {
    await input.first().setInputFiles(filePath);
    return "input[type='file']";
  }

  await clickFirstVisible(page, [
    "button:has-text('图生图')",
    "button:has-text('参考图')",
    "text=参考图",
    "button:has-text('上传')",
    "button:has-text('图片')",
    "[role='button']:has-text('上传')",
    "[role='button']:has-text('参考')",
    "button[aria-label*='上传']",
    "button[aria-label*='图片']",
    "button:has-text('+')",
    "[role='button']:has-text('+')",
  ]);

  input = page.locator("input[type='file']");
  if ((await input.count()) > 0) {
    await input.first().setInputFiles(filePath);
    return "trigger+input[type='file']";
  }
  return null;
}

async function fillPrompt(page, prompt) {
  const selectors = ["[contenteditable='true'][data-testid='chat_input_input']", "[contenteditable='true']", "textarea", "div[role='textbox']"];
  for (const selector of selectors) {
    const box = page.locator(selector).first();
    if ((await box.count()) === 0) {
      continue;
    }
    const visible = await box.isVisible().catch(() => false);
    if (!visible) {
      continue;
    }
    await box.click({ timeout: 3000 }).catch(() => {});
    await page.keyboard.press("Control+A").catch(() => {});
    await page.keyboard.type(prompt, { delay: 2 }).catch(() => {});

    let value = await box.textContent().catch(() => "");
    if (!value || value.trim().length === 0) {
      await page
        .evaluate((text) => {
          const editor =
            document.querySelector("[contenteditable='true'][data-testid='chat_input_input']") ||
            document.querySelector("[contenteditable='true']");
          if (!editor) {
            return;
          }
          editor.focus();
          const selection = window.getSelection();
          if (selection) {
            const range = document.createRange();
            range.selectNodeContents(editor);
            selection.removeAllRanges();
            selection.addRange(range);
          }
          document.execCommand("insertText", false, text);
        }, prompt)
        .catch(() => {});
      value = await box.textContent().catch(() => "");
    }

    if (value && value.trim().length > 0) {
      return selector;
    }
  }
  return null;
}

async function clickSendButton(page) {
  const selectors = [
    "button[data-testid='chat_input_send_button']",
    "#flow-end-msg-send",
    ".image-send-msg-button button",
  ];

  for (const selector of selectors) {
    const btn = page.locator(selector).first();
    if ((await btn.count()) === 0) {
      continue;
    }
    const visible = await btn.isVisible().catch(() => false);
    if (!visible) {
      continue;
    }

    for (let i = 0; i < 20; i += 1) {
      const disabledAttr = await btn.getAttribute("disabled").catch(() => null);
      const ariaDisabled = await btn.getAttribute("aria-disabled").catch(() => null);
      const disabled = disabledAttr !== null || ariaDisabled === "true";
      if (!disabled) {
        await btn.click({ timeout: 3000 }).catch(() => {});
        return selector;
      }
      await page.waitForTimeout(500);
    }
  }

  return null;
}

async function waitUntilLoggedIn(page, timeoutMs = 180000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const loginBtnVisible = await page
      .locator("button:has-text('登录'), [role='button']:has-text('登录'), text=/扫码登录|手机号|验证码/")
      .first()
      .isVisible()
      .catch(() => false);
    if (!loginBtnVisible) {
      return true;
    }
    await page.waitForTimeout(3000);
  }
  return false;
}

function looksLikeImageGenerationApi(url, method) {
  if (method !== "POST") {
    return false;
  }
  return /(doubao\.com|volces\.com|byteimg\.com|byted\.org)/i.test(url);
}

function sanitizeHeaders(headers) {
  const masked = { ...headers };
  const secretKeys = [
    "authorization",
    "cookie",
    "x-amz-security-token",
    "x-jwt-token",
    "x-auth-token",
    "x-tt-token",
    "x-tt-stub",
  ];
  for (const key of secretKeys) {
    if (masked[key]) {
      masked[key] = "[REDACTED]";
    }
  }
  return masked;
}

function sanitizeUrl(url) {
  if (!url) {
    return "";
  }
  return url.split("?")[0];
}

async function needLogin(page) {
  const selectors = [
    "button:has-text('登录')",
    "[role='button']:has-text('登录')",
    "text=/扫码登录|手机号|验证码/",
  ];
  for (const selector of selectors) {
    const visible = await page.locator(selector).first().isVisible().catch(() => false);
    if (visible) {
      return true;
    }
  }
  return false;
}

async function main() {
  const inputImagePath = process.argv[2] ? path.resolve(process.argv[2]) : DEFAULT_IMAGE_PATH;
  const outputImagePath = process.argv[3]
    ? path.resolve(process.argv[3])
    : path.join(OUTPUT_DIR, `04_generated_${nowTag()}.png`);

  if (!fs.existsSync(inputImagePath)) {
    throw new Error(`找不到输入图片: ${inputImagePath}`);
  }
  ensureParentDir(outputImagePath);

  const report = {
    success: false,
    startedAt: new Date().toISOString(),
    targetUrl: TARGET_URL,
    imagePath: inputImagePath,
    loginRequired: false,
    loginCompleted: false,
    actions: [],
    networkHits: [],
    output: {
      loadedScreenshot: path.join(OUTPUT_DIR, `01_loaded_${nowTag()}.png`),
      uploadedScreenshot: path.join(OUTPUT_DIR, `02_uploaded_${nowTag()}.png`),
      resultScreenshot: path.join(OUTPUT_DIR, `03_result_${nowTag()}.png`),
      generatedImage: outputImagePath,
      networkJson: path.join(OUTPUT_DIR, `network_${nowTag()}.json`),
      reportJson: path.join(OUTPUT_DIR, `report_${nowTag()}.json`),
    },
    error: "",
  };

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    channel: "msedge",
    headless: false,
    viewport: { width: 1440, height: 960 },
    args: ["--disable-dev-shm-usage"],
  });

  const page = context.pages()[0] || (await context.newPage());

  page.on("request", (req) => {
    const url = req.url();
    const method = req.method();
    if (!looksLikeImageGenerationApi(url, method)) {
      return;
    }
    report.networkHits.push({
      type: "request",
      at: new Date().toISOString(),
      method,
      url: sanitizeUrl(url),
      headers: sanitizeHeaders(req.headers()),
      postData: (req.postData() || "").slice(0, 5000),
    });
  });

  page.on("response", async (res) => {
    const req = res.request();
    const url = req.url();
    const method = req.method();
    if (!looksLikeImageGenerationApi(url, method)) {
      return;
    }
    let bodyText = "";
    try {
      bodyText = await res.text();
    } catch {
      bodyText = "";
    }
    report.networkHits.push({
      type: "response",
      at: new Date().toISOString(),
      method,
      url: sanitizeUrl(url),
      status: res.status(),
      statusText: res.statusText(),
      bodyText: bodyText.slice(0, 5000),
    });
  });

  try {
    await page.goto(TARGET_URL, { waitUntil: "domcontentloaded", timeout: 120000 });
    report.actions.push("打开豆包图片生成页面");
    await page.waitForTimeout(4000);
    await page.screenshot({ path: report.output.loadedScreenshot, fullPage: true });

    const loginVisible = await needLogin(page);

    if (loginVisible) {
      report.loginRequired = true;
      await clickFirstVisible(page, ["button:has-text('登录')", "[role='button']:has-text('登录')"]);
      report.actions.push("检测到登录，等待手动扫码登录（最长3分钟）");
      console.log("检测到登录弹窗，请在浏览器窗口中完成登录，脚本将自动继续...");
      const ok = await waitUntilLoggedIn(page, 300000);
      report.loginCompleted = ok;
      if (!ok) {
        throw new Error("等待登录超时（5分钟），未继续执行");
      }
      report.actions.push("登录完成，继续执行");
    }

    const uploadSelector = await uploadReferenceImage(page, inputImagePath);
    if (!uploadSelector) {
      throw new Error("未找到上传入口，无法上传参考图");
    }
    report.actions.push(`上传参考图: ${uploadSelector}`);
    await page.waitForTimeout(2500);
    await page.screenshot({ path: report.output.uploadedScreenshot, fullPage: true });

    const promptSelector = await fillPrompt(page, PROMPT_TEXT);
    if (!promptSelector) {
      throw new Error("未找到提示词输入框");
    }
    report.actions.push(`填入提示词: ${promptSelector}`);

    const ratio = await clickFirstVisible(page, ["button:has-text('1:1')", "[role='button']:has-text('1:1')"]);
    if (ratio) {
      report.actions.push("设置比例 1:1");
    }

    const quality = await clickFirstVisible(page, [
      "button:has-text('高清')",
      "button:has-text('高质量')",
      "[role='button']:has-text('高清')",
      "[role='button']:has-text('高质量')",
    ]);
    if (quality) {
      report.actions.push("设置高清/高质量");
    }

    const generateSelector = await clickSendButton(page);
    if (!generateSelector) {
      throw new Error("未找到可点击的发送/生成按钮，或按钮一直处于禁用状态");
    }
    report.actions.push(`点击生成: ${generateSelector}`);

    await page.waitForTimeout(45000);
    await page.screenshot({ path: report.output.resultScreenshot, fullPage: true });
    report.actions.push("等待45秒并截取结果页");

    const imageUrl = await page.evaluate(() => {
      const images = [...document.querySelectorAll("img")]
        .map((img) => ({
          src: img.currentSrc || img.src || "",
          width: img.naturalWidth || 0,
          height: img.naturalHeight || 0,
        }))
        .filter((x) => x.src && x.width >= 128 && x.height >= 128)
        .filter((x) => !/avatar|icon|logo/i.test(x.src))
        .filter((x) => /(byteimg|imagex|tos|doubao|flow)/i.test(x.src));
      return images.length > 0 ? images[0].src : "";
    });

    if (imageUrl) {
      try {
        const imgRes = await fetch(imageUrl);
        if (imgRes.ok) {
          const arrBuf = await imgRes.arrayBuffer();
          fs.writeFileSync(report.output.generatedImage, Buffer.from(arrBuf));
          report.actions.push("已下载首张生成图到本地");
          report.generatedImageUrl = sanitizeUrl(imageUrl);
        }
      } catch {
        report.actions.push("生成图下载失败，已保留页面截图");
      }
    } else {
      report.actions.push("未在页面中定位到可下载的生成图");
    }

    report.success = true;
  } catch (err) {
    report.error = String(err && err.message ? err.message : err);
  } finally {
    fs.writeFileSync(report.output.networkJson, JSON.stringify(report.networkHits, null, 2), "utf8");
    fs.writeFileSync(report.output.reportJson, JSON.stringify(report, null, 2), "utf8");
    console.log(
      JSON.stringify(
        {
          success: report.success,
          actions: report.actions,
          loginRequired: report.loginRequired,
          loginCompleted: report.loginCompleted,
          networkHitCount: report.networkHits.length,
          output: report.output,
          error: report.error,
        },
        null,
        2
      )
    );
    await context.close();
  }
}

main().catch((err) => {
  console.error(`[FATAL] ${err.message}`);
  process.exitCode = 1;
});
