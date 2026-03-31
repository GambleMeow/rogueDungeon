const { test } = require("@playwright/test");
const fs = require("fs");
const path = require("path");

const SOURCE_IMAGE = path.resolve(__dirname, "../icons/passives/PASBTNBash.png");
const OUTPUT_DIR = path.resolve(__dirname, "./doubao-output");

const PROMPT_TEXT =
  "对于图片中的主体抽象出来，然后重新生成一个游戏风格的图片。";

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

test.use({
  channel: "chrome",
  viewport: { width: 1440, height: 960 },
  launchOptions: { headless: true },
});

async function clickFirstVisible(page, selectors) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    const count = await locator.count();
    if (!count) {
      continue;
    }
    const visible = await locator.isVisible().catch(() => false);
    if (!visible) {
      continue;
    }
    await locator.click({ timeout: 3000 }).catch(() => {});
    await page.waitForTimeout(800);
    return selector;
  }
  return null;
}

async function uploadFile(page, filePath) {
  let input = page.locator("input[type='file']");
  if ((await input.count()) > 0) {
    await input.first().setInputFiles(filePath);
    return "input[type='file']";
  }

  await clickFirstVisible(page, [
    "button:has-text('图生图')",
    "button:has-text('参考图')",
    "button:has-text('上传')",
    "button:has-text('图片')",
    "button[aria-label*='上传']",
    "button[aria-label*='图片']",
    "[role='button']:has-text('上传')",
    "[role='button']:has-text('参考')",
  ]);

  input = page.locator("input[type='file']");
  if ((await input.count()) > 0) {
    await input.first().setInputFiles(filePath);
    return "trigger+input[type='file']";
  }

  await clickFirstVisible(page, [
    "button:has-text('+')",
    "[role='button']:has-text('+')",
    "button[aria-label*='附件']",
    "button[aria-label*='添加']",
  ]);

  input = page.locator("input[type='file']");
  if ((await input.count()) > 0) {
    await input.first().setInputFiles(filePath);
    return "plus+input[type='file']";
  }

  return null;
}

async function fillPrompt(page, text) {
  const selectors = ["textarea", "[contenteditable='true']", "div[role='textbox']"];
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    const count = await locator.count();
    if (!count) {
      continue;
    }
    const visible = await locator.isVisible().catch(() => false);
    if (!visible) {
      continue;
    }
    await locator.click({ timeout: 3000 }).catch(() => {});
    await locator.fill(text).catch(() => {});
    const typed = await locator.inputValue().catch(() => "");
    if (typed && typed.length > 0) {
      return selector;
    }
    await page.keyboard.press("Control+A").catch(() => {});
    await page.keyboard.type(text, { delay: 3 });
    return selector;
  }
  return null;
}

test("doubao image-to-image with PASBTNBash", async ({ page }) => {
  const reportPath = path.join(OUTPUT_DIR, "report.json");
  const report = {
    success: false,
    loginRequired: false,
    sourceImage: SOURCE_IMAGE,
    steps: [],
    error: "",
    files: {
      loadedScreenshot: path.join(OUTPUT_DIR, "01_loaded.png"),
      uploadedScreenshot: path.join(OUTPUT_DIR, "02_uploaded.png"),
      resultScreenshot: path.join(OUTPUT_DIR, "03_result.png"),
    },
  };

  if (!fs.existsSync(SOURCE_IMAGE)) {
    throw new Error(`参考图不存在: ${SOURCE_IMAGE}`);
  }

  try {
    await page.goto("https://www.doubao.com/chat/create-image", {
      waitUntil: "domcontentloaded",
      timeout: 120000,
    });
    report.steps.push("打开豆包图片页面");
    await page.waitForTimeout(5000);
    await page.screenshot({ path: report.files.loadedScreenshot, fullPage: true });

    const loginVisible = await page
      .locator("text=/登录|扫码|手机号|验证码/")
      .first()
      .isVisible()
      .catch(() => false);
    if (loginVisible) {
      report.loginRequired = true;
      report.steps.push("检测到登录提示，停止后续自动生成");
      fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
      return;
    }

    const uploadUsed = await uploadFile(page, SOURCE_IMAGE);
    if (!uploadUsed) {
      throw new Error("未找到可用的图片上传入口");
    }
    report.steps.push(`上传参考图成功，使用选择器路径: ${uploadUsed}`);
    await page.waitForTimeout(2500);
    await page.screenshot({ path: report.files.uploadedScreenshot, fullPage: true });

    const promptUsed = await fillPrompt(page, PROMPT_TEXT);
    if (!promptUsed) {
      throw new Error("未找到可输入提示词的输入框");
    }
    report.steps.push(`填入提示词成功，输入框选择器: ${promptUsed}`);

    const ratioClicked = await clickFirstVisible(page, [
      "button:has-text('1:1')",
      "[role='button']:has-text('1:1')",
    ]);
    if (ratioClicked) {
      report.steps.push("尝试设置比例为 1:1");
    }

    const qualityClicked = await clickFirstVisible(page, [
      "button:has-text('高清')",
      "button:has-text('高质量')",
      "[role='button']:has-text('高清')",
      "[role='button']:has-text('高质量')",
    ]);
    if (qualityClicked) {
      report.steps.push("尝试开启高清/高质量");
    }

    const beforeCount = await page.locator("img").count();
    const generateUsed = await clickFirstVisible(page, [
      "button:has-text('生成')",
      "button:has-text('立即生成')",
      "button:has-text('创作')",
      "button:has-text('发送')",
      "[role='button']:has-text('生成')",
      "button[aria-label*='发送']",
    ]);
    if (!generateUsed) {
      throw new Error("未找到生成按钮");
    }
    report.steps.push(`点击生成按钮，选择器: ${generateUsed}`);

    await page.waitForTimeout(45000);
    const afterCount = await page.locator("img").count();
    report.steps.push(`结果等待结束，img 数量变化: ${beforeCount} -> ${afterCount}`);

    await page.screenshot({ path: report.files.resultScreenshot, fullPage: true });
    report.success = true;
  } catch (error) {
    report.error = String(error && error.message ? error.message : error);
  } finally {
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
    console.log(JSON.stringify(report, null, 2));
  }
});
