const fs = require("fs");
const path = require("path");

const DEFAULT_INPUT = path.resolve(__dirname, "../icons/passives/PASBTNBash.png");
const DEFAULT_OUTPUT = path.resolve(__dirname, "./doubao-api-output/PASBTNBash_game_style.png");
const DEFAULT_PROMPT =
  "对于图片中的主体抽象出来，然后重新生成一个游戏风格的图片。";

function guessMimeByFile(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".png") {
    return "image/png";
  }
  if (ext === ".jpg" || ext === ".jpeg") {
    return "image/jpeg";
  }
  if (ext === ".webp") {
    return "image/webp";
  }
  return "application/octet-stream";
}

function ensureDir(filePath) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

async function postJson(url, apiKey, payload) {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw_text: text };
  }

  return {
    ok: res.ok,
    status: res.status,
    body: json,
  };
}

async function saveByResponseData(item, outputPath) {
  if (item && typeof item.b64_json === "string" && item.b64_json.length > 0) {
    const buffer = Buffer.from(item.b64_json, "base64");
    fs.writeFileSync(outputPath, buffer);
    return { mode: "b64_json", outputPath };
  }

  if (item && typeof item.url === "string" && item.url.length > 0) {
    const imgRes = await fetch(item.url);
    if (!imgRes.ok) {
      throw new Error(`下载生成图片失败: HTTP ${imgRes.status}`);
    }
    const arrayBuffer = await imgRes.arrayBuffer();
    fs.writeFileSync(outputPath, Buffer.from(arrayBuffer));
    return { mode: "url", outputPath, sourceUrl: item.url };
  }

  throw new Error("接口返回中未找到 data[0].b64_json 或 data[0].url");
}

async function run() {
  const apiKey = process.env.ARK_API_KEY || process.env.VOLCENGINE_API_KEY || "";
  const baseUrl = process.env.ARK_BASE_URL || "https://ark.cn-beijing.volces.com/api/v3";
  const model = process.env.ARK_IMAGE_MODEL || "doubao-seededit-3-0-i2i-250628";

  const inputPath = path.resolve(process.argv[2] || DEFAULT_INPUT);
  const outputPath = path.resolve(process.argv[3] || DEFAULT_OUTPUT);
  const prompt = process.env.ARK_IMAGE_PROMPT || DEFAULT_PROMPT;

  if (!apiKey) {
    throw new Error("缺少 API Key：请先在当前终端设置 ARK_API_KEY（或 VOLCENGINE_API_KEY）");
  }

  if (!fs.existsSync(inputPath)) {
    throw new Error(`输入图片不存在: ${inputPath}`);
  }

  const inputBuffer = fs.readFileSync(inputPath);
  const mime = guessMimeByFile(inputPath);
  const dataUri = `data:${mime};base64,${inputBuffer.toString("base64")}`;

  const basePayload = {
    model,
    prompt,
    image: dataUri,
    size: "adaptive",
    guidance_scale: 5.5,
    seed: 123,
    watermark: false,
  };

  const payloadVariants = [
    { ...basePayload, response_format: "b64_json" },
    { ...basePayload },
  ];

  const endpoints = ["/images/generations", "/images/edits"];
  let lastError = null;
  let responseBody = null;
  let usedEndpoint = null;
  let usedPayloadVariant = "";

  for (const payload of payloadVariants) {
    for (const endpoint of endpoints) {
      const url = `${baseUrl}${endpoint}`;
      const result = await postJson(url, apiKey, payload);

      if (result.ok) {
        responseBody = result.body;
        usedEndpoint = endpoint;
        usedPayloadVariant = payload.response_format ? "with_response_format" : "without_response_format";
        break;
      }

      lastError = new Error(
        `请求失败 ${endpoint} -> HTTP ${result.status}，返回: ${JSON.stringify(result.body).slice(0, 500)}`
      );
    }
    if (responseBody) {
      break;
    }
  }

  if (!responseBody || !responseBody.data || !responseBody.data[0]) {
    throw lastError || new Error("接口无可用结果，且未返回 data[0]");
  }

  ensureDir(outputPath);
  const saveResult = await saveByResponseData(responseBody.data[0], outputPath);

  console.log("调用成功");
  console.log(`endpoint: ${usedEndpoint}`);
  console.log(`payload_variant: ${usedPayloadVariant}`);
  console.log(`model: ${model}`);
  console.log(`input: ${inputPath}`);
  console.log(`output: ${saveResult.outputPath}`);
  if (saveResult.sourceUrl) {
    console.log(`result_url: ${saveResult.sourceUrl}`);
  }
}

run().catch((err) => {
  console.error(`[ERROR] ${err.message}`);
  process.exitCode = 1;
});
