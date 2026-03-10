/**
 * 下载 BOSS 图鉴帖子的图片
 */
const https = require('https');
const fs = require('fs');
const path = require('path');

const images = [
  "https://up5.nosdn.127.net/topic/db0c1bf6744b4cad8cd8ef06744586b8.png?size=1003*1519",
  "https://up5.nosdn.127.net/topic/00c64aa179624bbd96f6f33580ac05e6.png?size=1003*2416",
  "https://up5.nosdn.127.net/topic/893ddd45114e46509802dd0997b5bbd3.png?size=1003*1749",
  "https://up5.nosdn.127.net/topic/9a182c67269f485eab682944d5070899.png?size=1003*1703",
  "https://up5.nosdn.127.net/topic/ec75218aeea140e78cf89b8bcde1a138.png?size=1003*1749",
  "https://up5.nosdn.127.net/topic/2a060bd1f7b04dc18b68469a73ef17a6.png?size=1003*1866",
  "https://up5.nosdn.127.net/topic/5a2e2179fda840908edab41ec5dd3163.png?size=1003*2025",
  "https://up5.nosdn.127.net/topic/672dcd930f2d4892b736356583f3299b.png?size=1003*1519",
  "https://up5.nosdn.127.net/topic/9a9e2b0256f946daa7731cb642b6d41e.png?size=1003*1910",
  "https://up5.nosdn.127.net/topic/d3f2d01804684f71bb2e5c946219d33c.png?size=1003*2117",
  "https://up5.nosdn.127.net/topic/0dfa8135784c479f8d21f9621583a8a6.png?size=1003*1841",
  "https://up5.nosdn.127.net/topic/ede29fc5ce0a40c8865bcf44d1faf5e2.png?size=1003*1473",
  "https://up5.nosdn.127.net/topic/05ba061193964544bca83a66e0ca34b8.png?size=1003*1910",
  "https://up5.nosdn.127.net/topic/a8214750b0154406a0cfefb315ca79ba.png?size=1003*2439",
  "https://up5.nosdn.127.net/topic/591786992fe44d37abe0ecb424e54533.png?size=1003*2140",
  "https://up5.nosdn.127.net/topic/5098a3f21c0b47ed80a2d8385136bdd7.png?size=1003*2094",
  "https://up5.nosdn.127.net/topic/b542f6da423c40908379ced40eac871a.png?size=1003*1611",
  "https://up5.nosdn.127.net/topic/5c4e714fe0bc4c0d8c0e3100c29cfc39.png?size=1003*1680",
  "https://up5.nosdn.127.net/topic/5e53cb08eb924d05b448230b2fc05ff2.png?size=1003*1841",
  "https://up5.nosdn.127.net/topic/593720bab0fe43769417980e28adbdad.png?size=1003*1910",
  "https://up5.nosdn.127.net/topic/2210b939e55e435a8124bf60c12b57f9.png?size=1003*2266",
  "https://up5.nosdn.127.net/topic/091b60346fae42ee819298309676d2eb.png?size=1003*1565",
  "https://up5.nosdn.127.net/topic/50f3f72818da4c26a498060677eec318.png?size=1003*2253"
];

const dir = path.join(__dirname, 'boss-images');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

function download(url) {
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function main() {
  for (let i = 0; i < images.length; i++) {
    const f = path.join(dir, `img${String(i).padStart(2, '0')}.png`);
    try {
      const buf = await download(images[i]);
      fs.writeFileSync(f, buf);
      console.log(`Saved ${i}: ${f}`);
    } catch (e) {
      console.error(`Fail ${i}:`, e.message);
    }
  }
}
main();
