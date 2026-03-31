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

  const info = await page.evaluate(() => {
    const input =
      document.querySelector("[contenteditable='true']") ||
      document.querySelector("textarea") ||
      document.querySelector("div[role='textbox']");
    if (!input) {
      return { found: false };
    }
    let node = input;
    for (let i = 0; i < 6; i += 1) {
      if (!node || !node.parentElement) {
        break;
      }
      node = node.parentElement;
    }
    const html = (node && node.outerHTML) || "";

    const clickable = [...(node ? node.querySelectorAll("*") : [])]
      .filter((el) => {
        const role = el.getAttribute("role");
        const aria = el.getAttribute("aria-label");
        const hasClick = typeof el.onclick === "function";
        const cls = (el.className || "").toString();
        return (
          role === "button" ||
          el.tagName.toLowerCase() === "button" ||
          hasClick ||
          /cursor-pointer|pointer/.test(cls) ||
          (aria && aria.length > 0)
        );
      })
      .slice(0, 200)
      .map((el) => ({
        tag: el.tagName.toLowerCase(),
        text: (el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 40),
        aria: el.getAttribute("aria-label") || "",
        role: el.getAttribute("role") || "",
        className: (el.className || "").toString().slice(0, 160),
      }));

    return {
      found: true,
      html: html.slice(0, 40000),
      clickable,
    };
  });

  console.log(JSON.stringify(info, null, 2));
  await context.close();
}

main().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});
