const fs = require("fs");

const inputPath = process.argv[2];
if (!inputPath) {
  console.error("usage: node extract_completion_urls.js <network-json-path>");
  process.exit(1);
}

const raw = fs.readFileSync(inputPath, "utf8");
const data = JSON.parse(raw);
const completionResponses = data.filter(
  (x) => x.type === "response" && /\/samantha\/chat\/completion/.test(x.url || "")
);
const text = completionResponses.map((x) => x.bodyText || "").join("\n");
const urls = text.match(/https?:\/\/[^\s"']+/g) || [];
const uniqueUrls = [...new Set(urls)];
console.log(JSON.stringify(uniqueUrls, null, 2));
