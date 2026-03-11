const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");
const { parseMDX, decodeBLP, getBLPImageData } = require("war3-model");
const { Document, NodeIO } = require("@gltf-transform/core");

const WORK_DIR = "C:/Users/Administrator/Desktop/personal/rogueDungeon2/convert_boss027";
const MODEL_NAME = "boss_027";
const MDX_PATH = path.join(WORK_DIR, `${MODEL_NAME}.mdx`);
const OUT_GLB = path.join(WORK_DIR, `${MODEL_NAME}.glb`);

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function decodeBlpToPngBuffer(blpPath) {
  const data = fs.readFileSync(blpPath);
  const blp = decodeBLP(toArrayBuffer(data));
  const imageData = getBLPImageData(blp, 0);
  const png = new PNG({
    width: blp.width,
    height: blp.height,
    inputHasAlpha: true,
  });
  png.data = Buffer.from(imageData.data.buffer);
  return PNG.sync.write(png);
}

function buildTextureLookup(dir) {
  const files = fs.readdirSync(dir);
  const map = new Map();
  for (const file of files) {
    if (path.extname(file).toLowerCase() === ".blp") {
      map.set(file.toLowerCase(), path.join(dir, file));
    }
  }
  return map;
}

function pickTextureNameFromMaterial(model, materialId) {
  const material = model.Materials[materialId];
  if (!material || !material.Layers || material.Layers.length === 0) return null;
  const layer = material.Layers[0];
  if (typeof layer.TextureID !== "number") return null;
  const texDef = model.Textures[layer.TextureID];
  if (!texDef || !texDef.Image) return null;
  return path.basename(texDef.Image);
}

function run() {
  if (!fs.existsSync(MDX_PATH)) {
    throw new Error(`找不到模型文件: ${MDX_PATH}`);
  }

  const mdxBuffer = fs.readFileSync(MDX_PATH);
  const model = parseMDX(toArrayBuffer(mdxBuffer));
  const textureLookup = buildTextureLookup(WORK_DIR);

  const document = new Document();
  const root = document.getRoot();
  const buffer = document.createBuffer();
  const scene = document.createScene(`${MODEL_NAME}_scene`);
  const node = document.createNode(`${MODEL_NAME}_node`);
  const mesh = document.createMesh(`${MODEL_NAME}_mesh`);
  scene.addChild(node);
  node.setMesh(mesh);

  const materialCache = new Map();

  for (let i = 0; i < model.Geosets.length; i++) {
    const geoset = model.Geosets[i];
    if (!geoset || !geoset.Vertices || !geoset.Faces) continue;

    const position = document
      .createAccessor(`geo_${i}_POSITION`)
      .setType("VEC3")
      .setArray(new Float32Array(geoset.Vertices))
      .setBuffer(buffer);

    const primitive = document.createPrimitive().setAttribute("POSITION", position);

    if (geoset.Normals && geoset.Normals.length === geoset.Vertices.length) {
      const normal = document
        .createAccessor(`geo_${i}_NORMAL`)
        .setType("VEC3")
        .setArray(new Float32Array(geoset.Normals))
        .setBuffer(buffer);
      primitive.setAttribute("NORMAL", normal);
    }

    if (geoset.TVertices && geoset.TVertices[0]) {
      const uv = document
        .createAccessor(`geo_${i}_TEXCOORD_0`)
        .setType("VEC2")
        .setArray(new Float32Array(geoset.TVertices[0]))
        .setBuffer(buffer);
      primitive.setAttribute("TEXCOORD_0", uv);
    }

    const indexArray = new Uint32Array(geoset.Faces);
    const indices = document
      .createAccessor(`geo_${i}_INDICES`)
      .setType("SCALAR")
      .setArray(indexArray)
      .setBuffer(buffer);
    primitive.setIndices(indices);

    const materialId = geoset.MaterialID || 0;
    if (!materialCache.has(materialId)) {
      const mat = document
        .createMaterial(`mat_${materialId}`)
        .setDoubleSided(true)
        .setMetallicFactor(0)
        .setRoughnessFactor(1);

      const textureName = pickTextureNameFromMaterial(model, materialId);
      if (textureName) {
        const blpPath = textureLookup.get(textureName.toLowerCase());
        if (blpPath && fs.existsSync(blpPath)) {
          const pngBuffer = decodeBlpToPngBuffer(blpPath);
          const tex = document
            .createTexture(textureName)
            .setMimeType("image/png")
            .setImage(pngBuffer);
          mat.setBaseColorTexture(tex);
        }
      }
      materialCache.set(materialId, mat);
    }
    primitive.setMaterial(materialCache.get(materialId));
    mesh.addPrimitive(primitive);
  }

  const io = new NodeIO();
  io.write(OUT_GLB, document);
  console.log(`已生成: ${OUT_GLB}`);
}

run();
