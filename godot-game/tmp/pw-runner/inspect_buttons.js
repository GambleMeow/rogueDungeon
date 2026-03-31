const { chromium } = require("playwright");

async function main() {
  const context = await chromium.launchPersistentContext(
    "C:/Users/LENOVO/Documents/qqq/tmp/pw-runner/cdp-profile",
    {
      channel: "msedge",
      headless: false,
      viewport: { width: 1400, height: 900 },
    }
  );

  const page = context.pages()[0] || (await context.newPage());
  await page.goto("https://www.doubao.com/chat/create-image", {
    waitUntil: "domcontentloaded",
    timeout: 120000,
  });
  await page.waitForTimeout(5000);

  const data = await page.evaluate(() => {
    const nodes = [
      ...document.querySelectorAll("button, [role='button'], div[role='button'], span[role='button']"),
    ];
    return nodes
      .slice(0, 1200)
      .map((el) => ({
        tag: el.tagName.toLowerCase(),
        text: (el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 60),
        aria: el.getAttribute("aria-label") || "",
        title: el.getAttribute("title") || "",
        className: (el.className || "").toString().slice(0, 120),
      }))
      .filter((x) => x.text || x.aria || x.title);
  });

  console.log(JSON.stringify(data, null, 2));
  await context.close();
}

main().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});
