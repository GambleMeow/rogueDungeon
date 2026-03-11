const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

let PNG = null;
let decodeBLP = null;
let getBLPImageData = null;

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function ensureBlpDeps() {
  if (PNG && decodeBLP && getBLPImageData) return true;
  try {
    PNG = require("pngjs").PNG;
    const war3 = require("war3-model");
    decodeBLP = war3.decodeBLP;
    getBLPImageData = war3.getBLPImageData;
    return true;
  } catch {
    return false;
  }
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

function preparePngTexturesForBlender(inputPath) {
  const inputDir = path.dirname(inputPath);
  const files = fs.readdirSync(inputDir);
  const blpFiles = files.filter((f) => path.extname(f).toLowerCase() === ".blp");
  if (blpFiles.length === 0) return;
  if (!ensureBlpDeps()) {
    console.warn("警告: 缺少 BLP 解码依赖，无法预生成 PNG 贴图。");
    return;
  }
  const outDir = path.join(inputDir, "_gltf_textures");
  fs.mkdirSync(outDir, { recursive: true });
  for (const blp of blpFiles) {
    try {
      const blpPath = path.join(inputDir, blp);
      const pngPath = path.join(outDir, `${path.basename(blp, ".blp")}.png`);
      const pngBuf = decodeBlpToPngBuffer(blpPath);
      fs.writeFileSync(pngPath, pngBuf);
    } catch (err) {
      console.warn(`跳过贴图 ${blp}: ${String(err && err.message ? err.message : err)}`);
    }
  }
}

function usage() {
  console.log("用法:");
  console.log(
    "node blender_convert.js --blender \"C:\\\\path\\\\to\\\\blender.exe\" --input \"C:\\\\path\\\\model.mdx\" --output \"C:\\\\path\\\\model.glb\""
  );
  process.exit(1);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const key = argv[i];
    const val = argv[i + 1];
    if (!key.startsWith("--")) continue;
    args[key.slice(2)] = val;
    i++;
  }
  return args;
}

function makePythonScript(pyPath) {
  const code = String.raw`
import bpy
import sys
import os
from pathlib import Path

argv = sys.argv
if "--" not in argv:
    raise RuntimeError("参数错误: 缺少 -- 分隔符")
idx = argv.index("--")
user_args = argv[idx + 1:]
if len(user_args) < 2:
    raise RuntimeError("参数错误: 需要 input output")

input_path = user_args[0]
output_path = user_args[1]
input_dir = os.path.dirname(input_path)

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)
    for block in bpy.data.textures:
        bpy.data.textures.remove(block)
    for block in bpy.data.images:
        bpy.data.images.remove(block)

def import_model(path_in):
    ext = os.path.splitext(path_in)[1].lower()
    if ext in [".glb", ".gltf"]:
        bpy.ops.import_scene.gltf(filepath=path_in)
        return
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path_in)
        return
    if ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path_in)
        return
    if ext in [".mdx", ".mdl"]:
        # 兼容不同 Warcraft3 插件:
        # 1) import_scene.mdx / import_scene.mdl
        # 2) warcraft_3.import_mdl_mdx
        # 用 try 顺序尝试，避免 hasattr 在 bpy.ops 上误判。
        last_err = None
        try:
            bpy.ops.import_scene.mdx(filepath=path_in)
            return
        except Exception as e:
            last_err = e
        try:
            bpy.ops.import_scene.mdl(filepath=path_in)
            return
        except Exception as e:
            last_err = e
        try:
            bpy.ops.warcraft_3.import_mdl_mdx(filepath=path_in)
            return
        except Exception as e:
            last_err = e
        available = [x for x in dir(bpy.ops.import_scene) if not x.startswith("_")]
        raise RuntimeError(
            "MDX/MDL 导入失败。可用 import_scene 操作: "
            + ", ".join(available)
            + "; 最后错误: "
            + str(last_err)
        )
    raise RuntimeError("不支持的输入格式: " + ext)

def build_image_map(search_dir):
    image_map = {}
    exts = {".png", ".jpg", ".jpeg", ".tga", ".bmp", ".webp"}
    for root, _, files in os.walk(search_dir):
        for name in files:
            ext = os.path.splitext(name)[1].lower()
            if ext not in exts:
                continue
            full = os.path.join(root, name)
            key = os.path.splitext(name)[0].lower()
            if key not in image_map:
                image_map[key] = full
    return image_map

def ensure_image_loaded(path_in):
    path_norm = os.path.normpath(path_in)
    for img in bpy.data.images:
        if img.filepath and os.path.normpath(bpy.path.abspath(img.filepath)) == path_norm:
            return img
    try:
        return bpy.data.images.load(path_norm, check_existing=True)
    except Exception:
        return None

def normalize_image_paths(image_map, search_dir):
    for img in bpy.data.images:
        if img.source != 'FILE' or not img.filepath:
            continue
        abs_path = bpy.path.abspath(img.filepath)
        if os.path.isfile(abs_path):
            continue
        base = os.path.splitext(os.path.basename(img.filepath))[0].lower()
        candidate = image_map.get(base)
        if not candidate:
            direct = os.path.join(search_dir, os.path.basename(img.filepath))
            if os.path.isfile(direct):
                candidate = direct
        if candidate:
            img.filepath = candidate

def ensure_image_file_on_disk(img, out_dir):
    if not img:
        return None
    try:
        abs_path = bpy.path.abspath(img.filepath) if img.filepath else ""
    except Exception:
        abs_path = ""
    if abs_path and os.path.isfile(abs_path):
        return abs_path
    os.makedirs(out_dir, exist_ok=True)
    safe_name = img.name.replace("\\", "_").replace("/", "_")
    out_path = os.path.join(out_dir, safe_name + ".png")
    try:
        img.filepath_raw = out_path
        img.file_format = 'PNG'
        img.save()
        img.filepath = out_path
        return out_path
    except Exception:
        try:
            img.save_render(out_path)
            img.filepath = out_path
            return out_path
        except Exception:
            return None

def pick_image_for_material(mat, image_map):
    if mat and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and getattr(n, "image", None):
                return n.image
    mname = (mat.name if mat else "").split(".")[0].lower()
    if mname in image_map:
        return ensure_image_loaded(image_map[mname])
    for key in image_map:
        if key in mname or mname in key:
            return ensure_image_loaded(image_map[key])
    return None

def normalize_materials(mesh_objects, image_map):
    fallback_images = [img for img in bpy.data.images if getattr(img, "size", (0, 0))[0] > 0 and getattr(img, "size", (0, 0))[1] > 0]
    texture_cache_dir = os.path.join(input_dir, "_gltf_textures")
    for obj in mesh_objects:
        if obj.type != 'MESH' or not obj.data:
            continue
        if not obj.data.materials:
            mat = bpy.data.materials.new(name=f"{obj.name}_mat")
            obj.data.materials.append(mat)
        for i, mat in enumerate(obj.data.materials):
            if mat is None:
                mat = bpy.data.materials.new(name=f"{obj.name}_mat_{i}")
                obj.data.materials[i] = mat
            img = pick_image_for_material(mat, image_map)
            if not img and fallback_images:
                img = fallback_images[min(i, len(fallback_images) - 1)]
            if img:
                ensure_image_file_on_disk(img, texture_cache_dir)
            mat.use_nodes = True
            nt = mat.node_tree
            nt.nodes.clear()
            out = nt.nodes.new("ShaderNodeOutputMaterial")
            out.location = (300, 0)
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
            bsdf.location = (0, 0)
            nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
            if img:
                tex = nt.nodes.new("ShaderNodeTexImage")
                tex.location = (-320, 0)
                tex.image = img
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
                if "Alpha" in tex.outputs and "Alpha" in bsdf.inputs:
                    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
                    mat.blend_method = 'BLEND'
                    mat.shadow_method = 'CLIP'

def get_armature_for_mesh(obj, armatures):
    for mod in obj.modifiers:
        if mod.type == 'ARMATURE' and mod.object and mod.object.type == 'ARMATURE':
            return mod.object
    if len(armatures) == 1:
        return armatures[0]
    return None

def normalize_skin_parenting(mesh_objects, armatures):
    for obj in mesh_objects:
        if obj.type != 'MESH':
            continue
        arm = get_armature_for_mesh(obj, armatures)
        if not arm:
            continue
        if obj.parent != arm:
            obj.parent = arm
            obj.parent_type = 'OBJECT'

def duplicate_actions_with_valid_root():
    valid_actions = []
    for old_action in list(bpy.data.actions):
        if not old_action.fcurves:
            continue
        new_action = bpy.data.actions.new(name=f"{old_action.name}_GLTF")
        for fc in old_action.fcurves:
            group_name = fc.group.name if fc.group else ""
            new_fc = new_action.fcurves.new(
                data_path=fc.data_path,
                index=fc.array_index,
                action_group=group_name
            )
            new_fc.keyframe_points.add(len(fc.keyframe_points))
            for idx, kp in enumerate(fc.keyframe_points):
                nkp = new_fc.keyframe_points[idx]
                nkp.co = kp.co[:]
                nkp.handle_left = kp.handle_left[:]
                nkp.handle_right = kp.handle_right[:]
                nkp.interpolation = kp.interpolation
            new_fc.update()
        valid_actions.append(new_action)
    return valid_actions

def bind_actions_to_nla(target_obj, actions):
    if not target_obj:
        return
    if target_obj.animation_data is None:
        target_obj.animation_data_create()
    anim = target_obj.animation_data
    anim.action = None
    for track in list(anim.nla_tracks):
        anim.nla_tracks.remove(track)

    frame_start = None
    frame_end = None
    for action in actions:
        if not action.fcurves:
            continue
        start = int(action.frame_range[0])
        end = int(action.frame_range[1])
        if end <= start:
            continue
        track = anim.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, start, action)
        strip.frame_start = start
        strip.frame_end = end
        if frame_start is None or start < frame_start:
            frame_start = start
        if frame_end is None or end > frame_end:
            frame_end = end
    if frame_start is not None and frame_end is not None:
        bpy.context.scene.frame_start = frame_start
        bpy.context.scene.frame_end = frame_end

clear_scene()
import_model(input_path)

all_mesh_objects = [o for o in bpy.data.objects if o.type == 'MESH']
all_armatures = [o for o in bpy.data.objects if o.type == 'ARMATURE']
image_map = build_image_map(input_dir)
normalize_image_paths(image_map, input_dir)
normalize_materials(all_mesh_objects, image_map)
normalize_skin_parenting(all_mesh_objects, all_armatures)
actions = duplicate_actions_with_valid_root()
bind_target = all_armatures[0] if all_armatures else (all_mesh_objects[0] if all_mesh_objects else None)
bind_actions_to_nla(bind_target, actions)
try:
    bpy.ops.file.pack_all()
except Exception:
    pass

os.makedirs(os.path.dirname(output_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format='GLB',
    export_yup=True,
    export_apply=True,
    export_animations=True,
    export_nla_strips=True,
    export_force_sampling=True,
    export_frame_range=False,
    export_skins=True,
    export_materials='EXPORT'
)

print("转换完成:", output_path)
`;
  fs.writeFileSync(pyPath, code, "utf8");
}

function main() {
  const args = parseArgs(process.argv);
  const defaultBlenderPath =
    "C:\\Users\\Administrator\\Downloads\\blender-3.6.22-windows-x64\\blender.exe";
  const blenderPath =
    args.blender ||
    process.env.BLENDER_PATH ||
    (fs.existsSync(defaultBlenderPath) ? defaultBlenderPath : undefined);
  const inputPath = args.input;
  const outputPath = args.output;

  if (!blenderPath || !inputPath || !outputPath) usage();
  if (!fs.existsSync(blenderPath)) {
    throw new Error(`找不到 Blender 可执行文件: ${blenderPath}`);
  }
  if (!fs.existsSync(inputPath)) {
    throw new Error(`找不到输入模型: ${inputPath}`);
  }
  preparePngTexturesForBlender(inputPath);

  const pyPath = path.join(os.tmpdir(), "blender_convert_temp.py");
  makePythonScript(pyPath);

  const result = spawnSync(
    blenderPath,
    ["--background", "--python", pyPath, "--", inputPath, outputPath],
    { encoding: "utf8", stdio: "pipe" }
  );

  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);

  if (result.status !== 0) {
    throw new Error(`Blender 转换失败，退出码: ${result.status}`);
  }
  if (!fs.existsSync(outputPath)) {
    const detail = (result.stderr || result.stdout || "").slice(0, 4000);
    throw new Error(`Blender 返回成功但未生成输出文件: ${outputPath}\n${detail}`);
  }
}

try {
  main();
} catch (e) {
  console.error(String(e.message || e));
  process.exit(1);
}
