const fs = require("fs");
const https = require("https");
const url = "https://dl1.shwswl.cn/buding/mod/3DMGAME-KKrgdlV29982.rar";
const out = "3DMGAME-KKrgdlV29982.rar";

https
  .get(
    url,
    {
      headers: {
        "User-Agent": "Mozilla/5.0",
        Referer: "https://dl.3dmgame.com/"
      }
    },
    (res) => {
      if (res.statusCode !== 200) {
        console.error("HTTP", res.statusCode);
        process.exit(1);
      }
      const total = Number(res.headers["content-length"] || 0);
      let downloaded = 0;
      let nextLog = 10;
      const ws = fs.createWriteStream(out);
      res.on("data", (chunk) => {
        downloaded += chunk.length;
        if (total > 0) {
          const pct = Math.floor((downloaded / total) * 100);
          if (pct >= nextLog) {
            console.log(`download ${pct}% (${downloaded}/${total})`);
            nextLog += 10;
          }
        }
      });
      res.pipe(ws);
      ws.on("finish", () => {
        ws.close();
        console.log("download complete", out, downloaded);
      });
    }
  )
  .on("error", (err) => {
    console.error("download error", err.message);
    process.exit(1);
  });
