const fs = require("fs");

const s = fs.readFileSync("index-DAKrQpyz.js", "utf8");
const matches = [...s.matchAll(/https?:\/\/[^"'`\s)]+/g)].map((m) => m[0]);
const uniq = [...new Set(matches)];

const modelLike = uniq.filter((u) => /mdx|mdl|blp|fbx|obj|glb|gltf|w3x|mpq/i.test(u));
const domains = [...new Set(uniq.map((u) => u.split("/").slice(0, 3).join("/")))];

console.log("urlCount", uniq.length);
console.log("modelLikeCount", modelLike.length);
if (modelLike.length > 0) {
  for (const u of modelLike) console.log(u);
} else {
  console.log("no model-like urls");
}
console.log("domains:");
for (const d of domains) console.log(d);
