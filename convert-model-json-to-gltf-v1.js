const fs = require("fs");
const path = require("path");

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function arrFromNumberObject(v) {
  if (Array.isArray(v)) return v;
  if (!v || typeof v !== "object") return [];
  return Object.keys(v)
    .sort((a, b) => Number(a) - Number(b))
    .map((k) => v[k]);
}

function align4(n) {
  return (n + 3) & ~3;
}

function pushChunk(state, arrayBuffer, target) {
  const byteLength = arrayBuffer.byteLength;
  const aligned = align4(byteLength);
  const pad = aligned - byteLength;
  const byteOffset = state.total;
  state.parts.push(Buffer.from(arrayBuffer));
  if (pad > 0) state.parts.push(Buffer.alloc(pad));
  state.total += aligned;
  return { byteOffset, byteLength, target };
}

function toFloat32Buffer(values) {
  return new Float32Array(values).buffer;
}

function toUint32Buffer(values) {
  return new Uint32Array(values).buffer;
}

function sanitizeTextureName(raw) {
  return String(raw || "")
    .replace(/\0/g, "")
    .replace(/\//g, "_")
    .replace(/\\/g, "_")
    .replace(/[<>:"|?*]/g, "_")
    .replace(/\.blp$/i, ".png");
}

function buildTextureUri(model, geoset) {
  const matId = Number(geoset.MaterialID || 0);
  const mat = (model.Materials || [])[matId];
  if (!mat || !Array.isArray(mat.Layers) || mat.Layers.length === 0) return "";
  const texId = Number(mat.Layers[0].TextureID || 0);
  const tex = (model.Textures || [])[texId];
  if (!tex || !tex.Image) return "";
  return `../textures/${sanitizeTextureName(tex.Image)}`;
}

function minMaxFromVec3(values) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < values.length; i += 3) {
    const x = Number(values[i] || 0);
    const y = Number(values[i + 1] || 0);
    const z = Number(values[i + 2] || 0);
    if (x < min[0]) min[0] = x;
    if (y < min[1]) min[1] = y;
    if (z < min[2]) min[2] = z;
    if (x > max[0]) max[0] = x;
    if (y > max[1]) max[1] = y;
    if (z > max[2]) max[2] = z;
  }
  return { min, max };
}

function convertModelToGltf(model) {
  const gltf = {
    asset: { version: "2.0", generator: "convert-model-json-to-gltf-v1" },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes: [{ name: model?.Info?.Name || "War3Model", mesh: 0 }],
    meshes: [{ name: model?.Info?.Name || "War3Mesh", primitives: [] }],
    materials: [],
    samplers: [{ magFilter: 9729, minFilter: 9987, wrapS: 10497, wrapT: 10497 }],
    images: [],
    textures: [],
    buffers: [],
    bufferViews: [],
    accessors: []
  };

  const state = { parts: [], total: 0 };
  const materialByTexture = new Map();

  for (const geoset of model.Geosets || []) {
    const vertices = arrFromNumberObject(geoset.Vertices);
    const normalsRaw = arrFromNumberObject(geoset.Normals);
    const faces = arrFromNumberObject(geoset.Faces).map((x) => Number(x));
    if (vertices.length < 9 || faces.length < 3) continue;
    if (faces.length % 3 !== 0) continue;

    const vertexCount = Math.floor(vertices.length / 3);
    const normals = normalsRaw.length >= vertices.length ? normalsRaw.slice(0, vertices.length) : new Array(vertices.length).fill(0);

    let uvSource = [];
    if (Array.isArray(geoset.TVertices) && geoset.TVertices.length > 0) {
      uvSource = arrFromNumberObject(geoset.TVertices[0]);
    }
    const uv = new Array(vertexCount * 2).fill(0);
    const uvCount = Math.min(vertexCount, Math.floor(uvSource.length / 2));
    for (let i = 0; i < uvCount; i++) {
      uv[i * 2] = Number(uvSource[i * 2] || 0);
      uv[i * 2 + 1] = 1.0 - Number(uvSource[i * 2 + 1] || 0);
    }

    const posChunk = pushChunk(state, toFloat32Buffer(vertices), 34962);
    const nrmChunk = pushChunk(state, toFloat32Buffer(normals), 34962);
    const uvChunk = pushChunk(state, toFloat32Buffer(uv), 34962);
    const idxChunk = pushChunk(state, toUint32Buffer(faces), 34963);

    const posBV = gltf.bufferViews.push({
      buffer: 0,
      byteOffset: posChunk.byteOffset,
      byteLength: posChunk.byteLength,
      target: posChunk.target
    }) - 1;
    const nrmBV = gltf.bufferViews.push({
      buffer: 0,
      byteOffset: nrmChunk.byteOffset,
      byteLength: nrmChunk.byteLength,
      target: nrmChunk.target
    }) - 1;
    const uvBV = gltf.bufferViews.push({
      buffer: 0,
      byteOffset: uvChunk.byteOffset,
      byteLength: uvChunk.byteLength,
      target: uvChunk.target
    }) - 1;
    const idxBV = gltf.bufferViews.push({
      buffer: 0,
      byteOffset: idxChunk.byteOffset,
      byteLength: idxChunk.byteLength,
      target: idxChunk.target
    }) - 1;

    const mm = minMaxFromVec3(vertices);
    const posAcc = gltf.accessors.push({
      bufferView: posBV,
      componentType: 5126,
      count: vertexCount,
      type: "VEC3",
      min: mm.min,
      max: mm.max
    }) - 1;
    const nrmAcc = gltf.accessors.push({
      bufferView: nrmBV,
      componentType: 5126,
      count: vertexCount,
      type: "VEC3"
    }) - 1;
    const uvAcc = gltf.accessors.push({
      bufferView: uvBV,
      componentType: 5126,
      count: vertexCount,
      type: "VEC2"
    }) - 1;
    const idxAcc = gltf.accessors.push({
      bufferView: idxBV,
      componentType: 5125,
      count: faces.length,
      type: "SCALAR"
    }) - 1;

    const texUri = buildTextureUri(model, geoset);
    let materialIndex = -1;
    if (materialByTexture.has(texUri)) {
      materialIndex = materialByTexture.get(texUri);
    } else {
      const mat = {
        pbrMetallicRoughness: {
          baseColorFactor: [1, 1, 1, 1],
          metallicFactor: 0,
          roughnessFactor: 1
        }
      };
      if (texUri) {
        const imageIndex = gltf.images.push({ uri: texUri }) - 1;
        const textureIndex = gltf.textures.push({ sampler: 0, source: imageIndex }) - 1;
        mat.pbrMetallicRoughness.baseColorTexture = { index: textureIndex };
      }
      materialIndex = gltf.materials.push(mat) - 1;
      materialByTexture.set(texUri, materialIndex);
    }

    gltf.meshes[0].primitives.push({
      attributes: { POSITION: posAcc, NORMAL: nrmAcc, TEXCOORD_0: uvAcc },
      indices: idxAcc,
      material: materialIndex
    });
  }

  if (gltf.meshes[0].primitives.length === 0) {
    return null;
  }

  const bin = Buffer.concat(state.parts);
  gltf.buffers.push({ uri: "", byteLength: bin.byteLength });
  return { gltf, bin };
}

function main() {
  const inputDir = "godot-assets/models_json";
  const outputDir = "godot-assets/models_gltf";
  ensureDir(outputDir);
  const oldOut = fs.existsSync(outputDir) ? fs.readdirSync(outputDir) : [];
  for (const f of oldOut) {
    if (/\.(gltf|bin)$/i.test(f)) {
      fs.unlinkSync(path.join(outputDir, f));
    }
  }

  const files = fs.existsSync(inputDir) ? fs.readdirSync(inputDir).filter((f) => f.endsWith(".json")) : [];
  const rows = [];

  for (const file of files) {
    const srcPath = path.join(inputDir, file);
    try {
      const model = JSON.parse(fs.readFileSync(srcPath, "utf8"));
      const converted = convertModelToGltf(model);
      if (!converted) {
        rows.push({ sourceJson: srcPath.replace(/\\/g, "/"), ok: false, reason: "no valid primitives" });
        continue;
      }
      const base = file.replace(/\.json$/i, "");
      const gltfPath = path.join(outputDir, `${base}.gltf`);
      const binPath = path.join(outputDir, `${base}.bin`);
      converted.gltf.buffers[0].uri = `${base}.bin`;
      fs.writeFileSync(gltfPath, JSON.stringify(converted.gltf, null, 2), "utf8");
      fs.writeFileSync(binPath, converted.bin);
      rows.push({
        sourceJson: srcPath.replace(/\\/g, "/"),
        gltfPath: gltfPath.replace(/\\/g, "/"),
        binPath: binPath.replace(/\\/g, "/"),
        primitiveCount: converted.gltf.meshes[0].primitives.length,
        ok: true
      });
    } catch (e) {
      rows.push({
        sourceJson: srcPath.replace(/\\/g, "/"),
        ok: false,
        reason: String(e && e.message ? e.message : e)
      });
    }
  }

  const out = {
    meta: {
      version: "1.0-model-json-to-gltf-v1",
      generatedAt: "2026-03-10",
      total: rows.length,
      okCount: rows.filter((x) => x.ok).length,
      failedCount: rows.filter((x) => !x.ok).length
    },
    rows
  };
  fs.writeFileSync("godot_model_gltf_manifest_v1.json", JSON.stringify(out, null, 2), "utf8");
  console.log("godot_model_gltf_manifest_v1.json generated");
  console.log("MODEL_GLTF_SUMMARY", out.meta);
}

main();
