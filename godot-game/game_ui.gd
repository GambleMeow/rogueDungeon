extends CanvasLayer

@export var hero_controller_path: NodePath = NodePath("../HeroController")
@export var enemy_ai_path: NodePath = NodePath("../EnemyAI")
@export var net_session_controller_path: NodePath = NodePath("../NetSessionController")

var _hero_ctrl: Node3D
var _enemy_ai: Node3D
var _net_ctrl: Node
var _hero_hp_bar: ProgressBar
var _hero_hp_label: Label
var _hero_mp_bar: ProgressBar
var _hero_mp_label: Label
var _hero_name_label: Label
var _boss_hp_bar: ProgressBar
var _boss_hp_label: Label
var _flash_cd_label: Label
var _haste_cd_label: Label
var _q_skill_name_label: Label
var _w_skill_name_label: Label
var _portrait_rect: ColorRect
var _boss_portrait_rect: ColorRect
var _atk_label: Label
var _def_label: Label
var _spd_label: Label
var _atk_speed_label: Label
var _atk_interval_label: Label
var _atk_range_label: Label
var _cdr_label: Label
var _phys_crit_rate_label: Label
var _phys_crit_mul_label: Label
var _spell_crit_rate_label: Label
var _spell_crit_mul_label: Label
var _hp_regen_label: Label
var _mp_regen_label: Label
var _str_label: Label
var _agi_label: Label
var _int_label: Label
var _shop_panel: Panel
var _shop_visible: bool = false
var _inventory_slots: Array[PanelContainer] = []
var _inventory_icons: Array[TextureRect] = []
var _offered_grid: GridContainer
var _shop_level: int = 1
var _gold: int = 10000
var _shop_offered: Array[int] = []
var _destroy_mode: bool = false
var _destroy_hover_index: int = -1
var _observed_peer_id: int = 0
var _self_peer_id: int = 0
var _observed_remote_hero_state: Dictionary = {}
var _observed_remote_equipment_state: Dictionary = {}
var _last_inventory_signature: String = ""
var _shop_level_label: Label
var _gold_label: Label
var _upgrade_btn: Button
var _refresh_btn: Button
var _destroy_skill_panel: PanelContainer

const P := "res://icons/skills/"

const BUILD_TABS := ["全部", "初始", "过渡", "摧毁", "贷款", "三月", "自动", "战旗", "结算", "充能", "咒文", "火花", "特摧", "硬币", "诅咒", "消耗", "配件", "后期"]

const SHOP_ITEM_COUNT := {1: 4, 2: 4, 3: 5, 4: 5, 5: 5, 6: 6, 7: 6}
const SHOP_UPGRADE_COST := {1: 100, 2: 150, 3: 250, 4: 400, 5: 600, 6: 1000, 7: 0}
const SHOP_REFRESH_COST := 50
const ITEM_COST := {1: 50, 2: 100, 3: 150, 4: 250, 5: 400, 6: 600, 7: 1000}
const LEVEL_WEIGHTS := {
	1: {1: 100},
	2: {1: 50, 2: 50},
	3: {1: 20, 2: 40, 3: 40},
	4: {1: 10, 2: 20, 3: 35, 4: 35},
	5: {1: 5, 2: 15, 3: 20, 4: 30, 5: 30},
	6: {1: 5, 2: 10, 3: 15, 4: 20, 5: 25, 6: 25},
	7: {1: 5, 2: 5, 3: 10, 4: 15, 5: 20, 6: 25, 7: 20},
}

const RECIPES := [
	{"inputs": {"流星": 3}, "output": "星落怀表"},
	{"inputs": {"泰坦之怒": 3}, "output": "陨灭泰坦锤"},
	{"inputs": {"三月": 3}, "output": "泰坦化身"},
	{"inputs": {"霜火之珠": 1}, "output": "霜火皇冠", "extra_cost": 500},
]

const ITEM_DB := [
	{"name": "木盾", "icon": "BTNThornShield.png", "stat": "Lv1 | +3护甲 +50生命", "build": "初始"},
	{"name": "小刀", "icon": "BTNClawsOfAttack.png", "stat": "Lv1 | +5攻击力", "build": "初始"},
	{"name": "勇气勋章", "icon": "BTNMedalionOfCourage.png", "stat": "Lv1 | +2全属性", "build": "初始"},

	{"name": "生命护符", "icon": "BTNAmulet.png", "stat": "Lv1 | +150生命 喂宝珠垫子", "build": "过渡"},
	{"name": "橡果", "icon": "BTNAcorn.png", "stat": "Lv1 | +100生命 7级道具垫子", "build": "过渡"},
	{"name": "小树枝", "icon": "BTNEnchantedGemstone.png", "stat": "Lv2 | +1全属性 嫖6商店", "build": "过渡"},
	{"name": "火焰风衣", "icon": "BTNCloakOfFlames.png", "stat": "Lv3 | +8%法伤 反弹火伤", "build": "过渡"},
	{"name": "吊命娃娃", "icon": "BTNVialFull.png", "stat": "Lv3 | 死亡复活50%HP一次", "build": "过渡"},
	{"name": "窃魂灵翁", "icon": "BTNSoulGem.png", "stat": "Lv3 | 击杀+灵魂 +2全属性/层", "build": "过渡"},
	{"name": "雄鹰戒指", "icon": "BTNRingJadeFalcon.png", "stat": "Lv3 | +5敏 结算+100HP", "build": "过渡"},
	{"name": "私人贷卷", "icon": "BTNScroll.png", "stat": "Lv3 | 贷款200金 每波还息", "build": "过渡"},

	{"name": "空洞宝珠", "icon": "BTNOrbOfDarkness.png", "stat": "Lv5 | 吃3装备进化邪灵宝珠", "build": "摧毁"},
	{"name": "回收锤", "icon": "BTNStormHammer.png", "stat": "Lv5 | 摧毁+等级×2随机属性", "build": "摧毁"},
	{"name": "血羽之心", "icon": "BTNHeartOfSearinox.png", "stat": "Lv6 | 摧毁得层数 200层翻倍属性", "build": "摧毁"},
	{"name": "骨质风铃", "icon": "BTNBoneChimes.png", "stat": "Lv5 | 摧毁后三围≥道具总等级", "build": "摧毁"},
	{"name": "邪灵宝珠", "icon": "BTNOrb.png", "stat": "Lv7 | 空洞进化 层数叠全属性", "build": "摧毁"},
	{"name": "万宝锤", "icon": "BTNThunderClap.png", "stat": "Lv5 | 摧毁+1层数 前期撑场", "build": "摧毁"},

	{"name": "蓝港补给箱", "icon": "BTNIcyTreasureBox.png", "stat": "Lv5 | 每波补给+还贷 核心", "build": "贷款"},
	{"name": "VIP卡", "icon": "BTNChestOfGold.png", "stat": "Lv5 | 钱少概率高 +200%收益", "build": "贷款"},
	{"name": "流星", "icon": "BTNStarFall.png", "stat": "Lv5 | +15%法伤 3个合成怀表", "build": "贷款"},
	{"name": "星落怀表", "icon": "BTNStarWand.png", "stat": "Lv7 | 3流星合 +45%法伤+陨落", "build": "贷款"},
	{"name": "贷款头盔", "icon": "BTNHelmOfValor.png", "stat": "Lv5 | +8%暴击 贷款毕业装", "build": "贷款"},
	{"name": "贷款盾", "icon": "BTNManaShield.png", "stat": "Lv5 | +12护甲 +格挡 毕业装", "build": "贷款"},
	{"name": "夹层硬币", "icon": "BTNTransmute.png", "stat": "Lv3 | 免费嫖VIP 减少花费", "build": "贷款"},

	{"name": "三月", "icon": "BTNMoonStone.png", "stat": "Lv6 | 3个合成Lv7 +大量全属性", "build": "三月"},
	{"name": "账本", "icon": "BTNTome.png", "stat": "Lv6 | 结算效果额外触发一次", "build": "三月"},
	{"name": "窃魂", "icon": "BTNUsedSoulGem.png", "stat": "Lv4 | 叠灵魂层数 词缀装备", "build": "三月"},
	{"name": "泰坦图腾", "icon": "BTNTaurenTotem.png", "stat": "Lv4 | +12力量 词缀加成", "build": "三月"},

	{"name": "自动机枪", "icon": "BTNInfernalCannon.png", "stat": "Lv6 | 自动攻击 装入组装器", "build": "自动"},
	{"name": "闪光放射器", "icon": "BTNInfernalFlameCannon.png", "stat": "Lv6 | 信标触发+法伤叠加", "build": "自动"},
	{"name": "组装器", "icon": "BTNBox.png", "stat": "Lv6 | 装入武器 可升级为信标", "build": "自动"},
	{"name": "信标", "icon": "BTNInfernalStone.png", "stat": "Lv6 | 定期触发武器 自动核心", "build": "自动"},
	{"name": "耐文合金", "icon": "BTNThoriumArmor.png", "stat": "Lv5 | +15护甲 +500生命", "build": "自动"},

	{"name": "英灵旗布", "icon": "BTNHumanCaptureFlag.png", "stat": "Lv5 | 旗帜层数翻倍 核心", "build": "战旗"},
	{"name": "银月", "icon": "BTNMoonKey.png", "stat": "Lv5 | +20%法伤 +10智力", "build": "战旗"},
	{"name": "全属性旗", "icon": "BTNNightElfCaptureFlag.png", "stat": "Lv4 | +3全属性/每层", "build": "战旗"},
	{"name": "法伤旗", "icon": "BTNOrcCaptureFlag.png", "stat": "Lv4 | +5%法伤/每层", "build": "战旗"},

	{"name": "审判金剑", "icon": "BTNFrostMourne.png", "stat": "Lv6 | 每结算装+2敏智+1%暴击", "build": "结算"},
	{"name": "金色账簿", "icon": "BTNTomeBrown.png", "stat": "Lv6 | 结算效果额外触发 核心", "build": "结算"},
	{"name": "雄狮之戒", "icon": "BTNRingLionHead.png", "stat": "Lv5 | +8敏 结算+200HP", "build": "结算"},
	{"name": "开辟者", "icon": "BTNScepterOfMastery.png", "stat": "Lv5 | +25%暴击伤害", "build": "结算"},
	{"name": "恶鬼剑", "icon": "BTNSacrificialSkull.png", "stat": "Lv5 | +15%暴击伤害", "build": "结算"},
	{"name": "钥匙", "icon": "BTNGhostKey.png", "stat": "Lv4 | +10%暴击率 英雄适配", "build": "结算"},

	{"name": "充能剑", "icon": "BTNDaggerOfEscape.png", "stat": "Lv5 | 充能攻击+50%伤害", "build": "充能"},
	{"name": "扳指", "icon": "BTNRingPurple.png", "stat": "Lv5 | +5全属性 攻击获充能层", "build": "充能"},
	{"name": "通灵杖", "icon": "BTNStaffOfNegation.png", "stat": "Lv5 | +10智力 技能伤害+20%", "build": "充能"},
	{"name": "完美核心", "icon": "BTNCrystalBall.png", "stat": "Lv6 | 充能满释放能量波 +8全属性", "build": "充能"},
	{"name": "充能齿轮", "icon": "BTNPocketFactory.png", "stat": "Lv5 | 充能核心装备 +充能效率", "build": "充能"},
	{"name": "粒子充能瓶", "icon": "BTNPotionBlueBig.png", "stat": "Lv5 | 高级充能瓶 大量充能层", "build": "充能"},

	{"name": "卡德加", "icon": "BTNSpellBookBLS.png", "stat": "Lv6 | 咒文效果+50% 法器核心", "build": "咒文"},
	{"name": "通灵长袍", "icon": "BTNRobeOfTheMagi.png", "stat": "Lv5 | +15智力 召唤物+30%伤", "build": "咒文"},
	{"name": "咒文灵翁", "icon": "BTNSobiMask.png", "stat": "Lv5 | 吃灵魂补主属性 咒文+1层", "build": "咒文"},
	{"name": "咒文匣子", "icon": "BTNCrate.png", "stat": "Lv6 | 存储咒文自动释放 法伤核心", "build": "咒文"},

	{"name": "泰坦之怒", "icon": "BTNHammer.png", "stat": "Lv5 | +30攻击 火花爆炸 3合陨灭", "build": "火花"},
	{"name": "火花环刃", "icon": "BTNUpgradeMoonGlaive.png", "stat": "Lv5 | +500生命 叠血核心", "build": "火花"},
	{"name": "遗留者眼球", "icon": "BTNOrbOfFire.png", "stat": "Lv5 | +法伤 火花伤害×10倍", "build": "火花"},
	{"name": "符文石", "icon": "BTNRunedBracers.png", "stat": "Lv4 | +300生命 叠血辅助", "build": "火花"},
	{"name": "破败之刃", "icon": "BTNOrbOfCorruption.png", "stat": "Lv5 | 按%目标最大生命造伤", "build": "火花"},
	{"name": "陨灭泰坦锤", "icon": "BTNGolemThunderClap.png", "stat": "Lv7 | 3泰坦怒合成 +90攻击", "build": "火花"},
	{"name": "火花灵翁", "icon": "BTNMarkOfFire.png", "stat": "Lv5 | 吃灵魂加攻速 火花辅助", "build": "火花"},

	{"name": "闪耀之爪", "icon": "BTNBearBlink.png", "stat": "Lv5 | 闪耀特效 300层超破败", "build": "特摧"},
	{"name": "霜火之珠", "icon": "BTNOrbOfFrost.png", "stat": "Lv5 | 升级成皇冠白嫖火花等级", "build": "特摧"},
	{"name": "霜火皇冠", "icon": "BTNHelmutPurple.png", "stat": "Lv6 | 白嫖火花等级 可喂宝珠", "build": "特摧"},

	{"name": "刷新币", "icon": "BTNPotionOfClarity.png", "stat": "Lv5 | 刷新商店获额外效果 必买", "build": "硬币"},
	{"name": "金硬币", "icon": "BTNPotionOfDivinity.png", "stat": "Lv5 | 获大量金币经验 核心", "build": "硬币"},
	{"name": "通天锤", "icon": "BTNGolemStormBolt.png", "stat": "Lv6 | 摧毁+1层数 30次后刷天赋", "build": "硬币"},

	{"name": "剑圣诅咒", "icon": "BTNWandSkull.png", "stat": "Lv5 | 攻击力转化全伤害 物理神", "build": "诅咒"},
	{"name": "血法诅咒", "icon": "BTNBloodLust.png", "stat": "Lv5 | 法术攻击+暴击 充能15波锁", "build": "诅咒"},
	{"name": "牛头人诅咒", "icon": "BTNCurse.png", "stat": "Lv5 | 燃烧+全能加成 牛头核心", "build": "诅咒"},
	{"name": "萨满诅咒", "icon": "BTNBigBadVoodooSpell.png", "stat": "Lv5 | 咒文召唤强化 咒文流用", "build": "诅咒"},

	{"name": "充能瓶", "icon": "BTNPotionBlue.png", "stat": "Lv3 | 消耗品 充n个电池叠充能", "build": "消耗"},
	{"name": "充能电池", "icon": "BTNPendantOfEnergy.png", "stat": "Lv3 | 消耗品 电池充充能瓶循环", "build": "消耗"},
	{"name": "经验币", "icon": "BTNPotionGreen.png", "stat": "Lv3 | 消耗品 获大量经验值", "build": "消耗"},
	{"name": "金印", "icon": "BTNGlyph.png", "stat": "Lv4 | 消耗品 咒文替代 没匣子先用", "build": "消耗"},
	{"name": "灵魂", "icon": "BTNSpiritWolf.png", "stat": "Lv2 | 消耗品 灵翁/窃魂获得", "build": "消耗"},
	{"name": "咒文消耗", "icon": "BTNSpellSteal.png", "stat": "Lv3 | 消耗品 吃加主属性 挑便宜", "build": "消耗"},

	{"name": "龙蛋", "icon": "BTNPhoenixEgg.png", "stat": "Lv4 | 配件 龙血沸腾+5特效/层", "build": "配件"},
	{"name": "望远镜", "icon": "BTNFarSight.png", "stat": "Lv4 | 配件 龙蛋流 电池点给它", "build": "配件"},
	{"name": "电磁屏障", "icon": "BTNNeutralManaShield.png", "stat": "Lv4 | 配件 防御护盾减伤", "build": "配件"},
	{"name": "无敌斩", "icon": "BTNDivineShieldOff.png", "stat": "Lv4 | 配件 剑圣专用 无敌W", "build": "配件"},
	{"name": "怨恨头骨", "icon": "BTNRingSkull.png", "stat": "Lv4 | 配件 死后灵体无敌平A", "build": "配件"},

	{"name": "不详", "icon": "BTNGuldanSkull.png", "stat": "Lv6 | +25%暴击率 15波后锁", "build": "后期"},
	{"name": "泰坦法杖", "icon": "BTNStaffOfTeleportation.png", "stat": "Lv6 | 法术伤害翻倍 大法师神", "build": "后期"},
	{"name": "唤醒泰坦杖", "icon": "BTNStaffOfSanctuary.png", "stat": "Lv6 | 5泰坦装合成泰坦化身", "build": "后期"},
	{"name": "泰坦化身", "icon": "BTNFleshGolem.png", "stat": "Lv7 | 全属性翻倍 8K+血 10W+伤", "build": "后期"},
	{"name": "月牙塔", "icon": "BTNAncientOfTheMoon.png", "stat": "Lv6 | +法伤 后期4月牙2合金", "build": "后期"},
	{"name": "噬魂", "icon": "BTNSpiritLink.png", "stat": "Lv6 | 吃灵魂+攻速 几万攻速可达", "build": "后期"},
	{"name": "暴击头盔", "icon": "BTNHumanArmorUpThree.png", "stat": "Lv5 | +10%暴击率 18波换装", "build": "后期"},
	{"name": "暴击斧", "icon": "BTNCriticalStrike.png", "stat": "Lv5 | +20%暴击伤害 恶鬼替代", "build": "后期"},
]

const COLOR_BG := Color(0.08, 0.06, 0.12, 0.92)
const COLOR_BORDER := Color(0.78, 0.66, 0.2, 1.0)
const COLOR_BORDER_DARK := Color(0.45, 0.35, 0.1, 1.0)
const COLOR_HP_FULL := Color(0.1, 0.85, 0.1, 1.0)
const COLOR_HP_LOW := Color(0.9, 0.15, 0.1, 1.0)
const COLOR_MP := Color(0.15, 0.35, 0.95, 1.0)
const COLOR_TEXT := Color(0.95, 0.92, 0.78, 1.0)
const COLOR_TEXT_DIM := Color(0.6, 0.55, 0.45, 1.0)
const COLOR_BUTTON_BG := Color(0.12, 0.1, 0.18, 1.0)
const COLOR_BUTTON_BORDER := Color(0.55, 0.45, 0.15, 1.0)
const COLOR_PORTRAIT_BG := Color(0.05, 0.04, 0.08, 1.0)

var PANEL_HEIGHT := 240


func _ready() -> void:
	_hero_ctrl = get_node_or_null(hero_controller_path)
	_enemy_ai = get_node_or_null(enemy_ai_path)
	_net_ctrl = get_node_or_null(net_session_controller_path)
	_build_ui()
	_apply_inventory_bonuses_to_hero()
	if _hero_ctrl != null and _hero_ctrl.has_method("set_destroy_cursor_mode"):
		_hero_ctrl.call("set_destroy_cursor_mode", false)
	_sync_destroy_hover_cursor()
	_refresh_inventory()


func _process(_delta: float) -> void:
	_update_network_view_state()
	_update_hero_info()
	_update_boss_info()
	_update_skill_name_labels()
	_update_flash_cd()
	_update_haste_cd()
	_check_shop_click()
	if _shop_visible:
		_update_shop_info()
	_refresh_inventory()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bottom_panel := Panel.new()
	bottom_panel.name = "BottomPanel"
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_top = -PANEL_HEIGHT
	bottom_panel.offset_bottom = 0
	bottom_panel.offset_left = 0
	bottom_panel.offset_right = 0
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = COLOR_BG
	panel_sb.border_color = COLOR_BORDER
	panel_sb.border_width_top = 3
	panel_sb.border_width_left = 0
	panel_sb.border_width_right = 0
	panel_sb.border_width_bottom = 0
	panel_sb.corner_radius_top_left = 0
	panel_sb.corner_radius_top_right = 0
	bottom_panel.add_theme_stylebox_override("panel", panel_sb)
	root.add_child(bottom_panel)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8
	hbox.offset_right = -8
	hbox.offset_top = 8
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 10)
	bottom_panel.add_child(hbox)

	_build_minimap_section(hbox)
	_build_hero_info_section(hbox)
	_build_command_section(hbox)
	_build_boss_info_section(hbox)
	_build_shop_panel(root)


func _build_minimap_section(parent: HBoxContainer) -> void:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(PANEL_HEIGHT - 16, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.04, 1.0)
	sb.border_color = COLOR_BORDER_DARK
	sb.set_border_width_all(2)
	container.add_theme_stylebox_override("panel", sb)
	parent.add_child(container)

	var label := Label.new()
	label.text = "MINIMAP"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	label.add_theme_font_size_override("font_size", 12)
	container.add_child(label)


func _build_hero_info_section(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.1, 1.0)
	sb.border_color = COLOR_BORDER_DARK
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var margin_left := MarginContainer.new()
	margin_left.add_theme_constant_override("margin_left", 8)
	margin_left.add_theme_constant_override("margin_top", 8)
	margin_left.add_theme_constant_override("margin_bottom", 8)
	hbox.add_child(margin_left)

	_portrait_rect = ColorRect.new()
	_portrait_rect.custom_minimum_size = Vector2(100, 0)
	_portrait_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait_rect.color = COLOR_PORTRAIT_BG
	margin_left.add_child(_portrait_rect)

	var portrait_border := ReferenceRect.new()
	portrait_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_border.border_color = COLOR_BORDER
	portrait_border.border_width = 2.0
	portrait_border.editor_only = false
	_portrait_rect.add_child(portrait_border)

	var portrait_label := Label.new()
	portrait_label.text = "HERO"
	portrait_label.set_anchors_preset(Control.PRESET_CENTER)
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	portrait_label.add_theme_font_size_override("font_size", 14)
	_portrait_rect.add_child(portrait_label)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)

	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 6)
	info_vbox.add_child(spacer_top)

	var name_label := Label.new()
	name_label.text = "英雄守望者"
	name_label.add_theme_color_override("font_color", COLOR_BORDER)
	name_label.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(name_label)
	_hero_name_label = name_label

	var hp_container := _create_bar_row("HP", COLOR_HP_FULL)
	info_vbox.add_child(hp_container)
	_hero_hp_bar = hp_container.get_node("Bar") as ProgressBar
	_hero_hp_label = hp_container.get_node("ValueLabel") as Label

	var mp_container := _create_bar_row("MP", COLOR_MP)
	info_vbox.add_child(mp_container)
	_hero_mp_bar = mp_container.get_node("Bar") as ProgressBar
	_hero_mp_bar.value = 100
	_hero_mp_label = mp_container.get_node("ValueLabel") as Label
	_hero_mp_label.text = "100 / 100"

	var stats_hbox := HBoxContainer.new()
	stats_hbox.add_theme_constant_override("separation", 20)
	info_vbox.add_child(stats_hbox)

	_atk_label = _create_stat_label(stats_hbox, "攻击: 20")
	_def_label = _create_stat_label(stats_hbox, "护甲: 5")
	_spd_label = _create_stat_label(stats_hbox, "移速: 200")

	var combat_hbox := HBoxContainer.new()
	combat_hbox.add_theme_constant_override("separation", 20)
	info_vbox.add_child(combat_hbox)
	_atk_speed_label = _create_stat_label(combat_hbox, "攻速: 2.00")
	_atk_interval_label = _create_stat_label(combat_hbox, "攻间隔: 0.50")
	_atk_range_label = _create_stat_label(combat_hbox, "攻距: 250")
	_cdr_label = _create_stat_label(combat_hbox, "冷却减免: 0.0%")

	var crit_hbox := HBoxContainer.new()
	crit_hbox.add_theme_constant_override("separation", 20)
	info_vbox.add_child(crit_hbox)
	_phys_crit_rate_label = _create_stat_label(crit_hbox, "物暴率: 0.0%")
	_phys_crit_mul_label = _create_stat_label(crit_hbox, "物暴倍: 2.00x")
	_spell_crit_rate_label = _create_stat_label(crit_hbox, "法暴率: 0.0%")
	_spell_crit_mul_label = _create_stat_label(crit_hbox, "法暴倍: 2.00x")

	var regen_hbox := HBoxContainer.new()
	regen_hbox.add_theme_constant_override("separation", 20)
	info_vbox.add_child(regen_hbox)
	_hp_regen_label = _create_stat_label(regen_hbox, "回血: 0.00/s")
	_mp_regen_label = _create_stat_label(regen_hbox, "回蓝: 0.00/s")

	var attr_hbox := HBoxContainer.new()
	attr_hbox.add_theme_constant_override("separation", 20)
	info_vbox.add_child(attr_hbox)
	_str_label = _create_stat_label(attr_hbox, "力量: 24")
	_agi_label = _create_stat_label(attr_hbox, "敏捷: 12")
	_int_label = _create_stat_label(attr_hbox, "智力: 14")

	var inv_margin := MarginContainer.new()
	inv_margin.add_theme_constant_override("margin_top", 8)
	inv_margin.add_theme_constant_override("margin_right", 8)
	inv_margin.add_theme_constant_override("margin_bottom", 8)
	hbox.add_child(inv_margin)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 2)
	inv_margin.add_child(inv_vbox)

	var inv_title := Label.new()
	inv_title.text = "物品栏"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	inv_title.add_theme_font_size_override("font_size", 11)
	inv_vbox.add_child(inv_title)

	var inv_grid := GridContainer.new()
	inv_grid.columns = 2
	inv_grid.add_theme_constant_override("h_separation", 3)
	inv_grid.add_theme_constant_override("v_separation", 3)
	inv_vbox.add_child(inv_grid)

	for i in range(6):
		var slot := _create_inventory_slot(i + 1)
		inv_grid.add_child(slot)
		_inventory_slots.append(slot)
		slot.gui_input.connect(_on_inv_slot_input.bind(i))
		slot.mouse_entered.connect(_on_inv_slot_mouse_entered.bind(i))
		slot.mouse_exited.connect(_on_inv_slot_mouse_exited.bind(i))
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var tex_rect := TextureRect.new()
		tex_rect.name = "ItemIcon"
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.visible = false
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex_rect)
		_inventory_icons.append(tex_rect)


func _build_command_section(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.2
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.1, 1.0)
	sb.border_color = COLOR_BORDER_DARK
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	margin.add_child(grid)

	var skill_data := [
		{"key": "Q", "name": "闪现", "active": true},
		{"key": "W", "name": "急速", "active": true},
		{"key": "E", "name": "", "active": false},
		{"key": "R", "name": "", "active": false},
		{"key": "A", "name": "攻击", "active": true},
		{"key": "F", "name": "摧毁", "active": true},
		{"key": "S", "name": "停止", "active": false},
		{"key": "P", "name": "巡逻", "active": false},
	]

	for data in skill_data:
		var btn := _create_skill_button(data["key"], data["name"], data["active"])
		grid.add_child(btn)
		if data["key"] == "Q":
			_flash_cd_label = btn.get_node("CDLabel") as Label
			_q_skill_name_label = btn.get_node_or_null("NameLabel") as Label
		if data["key"] == "W":
			_haste_cd_label = btn.get_node("CDLabel") as Label
			_w_skill_name_label = btn.get_node_or_null("NameLabel") as Label
		if data["key"] == "F":
			_destroy_skill_panel = btn


func _build_boss_info_section(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.04, 0.04, 1.0)
	sb.border_color = Color(0.7, 0.2, 0.15, 1.0)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var margin_top := MarginContainer.new()
	margin_top.add_theme_constant_override("margin_left", 8)
	margin_top.add_theme_constant_override("margin_top", 6)
	margin_top.add_theme_constant_override("margin_right", 8)
	vbox.add_child(margin_top)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 4)
	margin_top.add_child(inner_vbox)

	var boss_title := Label.new()
	boss_title.text = "★ BOSS - 牛头人酋长"
	boss_title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1.0))
	boss_title.add_theme_font_size_override("font_size", 14)
	inner_vbox.add_child(boss_title)

	_boss_portrait_rect = ColorRect.new()
	_boss_portrait_rect.custom_minimum_size = Vector2(0, 50)
	_boss_portrait_rect.color = Color(0.08, 0.03, 0.03, 1.0)
	inner_vbox.add_child(_boss_portrait_rect)

	var boss_portrait_label := Label.new()
	boss_portrait_label.text = "BOSS"
	boss_portrait_label.set_anchors_preset(Control.PRESET_CENTER)
	boss_portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_portrait_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	boss_portrait_label.add_theme_font_size_override("font_size", 11)
	_boss_portrait_rect.add_child(boss_portrait_label)

	var hp_row := _create_bar_row("HP", Color(0.9, 0.2, 0.15, 1.0))
	inner_vbox.add_child(hp_row)
	_boss_hp_bar = hp_row.get_node("Bar") as ProgressBar
	_boss_hp_label = hp_row.get_node("ValueLabel") as Label


func _create_bar_row(label_text: String, bar_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(28, 0)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(160, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.1, 0.15, 1.0)
	bar_bg.border_color = Color(0.3, 0.25, 0.2, 1.0)
	bar_bg.set_border_width_all(1)
	bar_bg.corner_radius_top_left = 2
	bar_bg.corner_radius_top_right = 2
	bar_bg.corner_radius_bottom_left = 2
	bar_bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = bar_color
	bar_fill.corner_radius_top_left = 2
	bar_fill.corner_radius_top_right = 2
	bar_fill.corner_radius_bottom_left = 2
	bar_fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", bar_fill)
	row.add_child(bar)

	var val_label := Label.new()
	val_label.name = "ValueLabel"
	val_label.text = "--- / ---"
	val_label.custom_minimum_size = Vector2(100, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_label.add_theme_color_override("font_color", COLOR_TEXT)
	val_label.add_theme_font_size_override("font_size", 12)
	row.add_child(val_label)

	return row


func _create_stat_label(parent: HBoxContainer, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)
	return lbl


func _set_tooltip_if_changed(ctrl: Control, text: String) -> void:
	if ctrl == null:
		return
	if ctrl.tooltip_text == text:
		return
	ctrl.tooltip_text = text


func _create_inventory_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(38, 38)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.09, 1.0)
	sb.border_color = COLOR_BORDER_DARK
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	slot.add_theme_stylebox_override("panel", sb)

	var num_label := Label.new()
	num_label.text = str(index)
	num_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	num_label.position = Vector2(-12, -18)
	num_label.add_theme_color_override("font_color", Color(0.3, 0.25, 0.2, 0.6))
	num_label.add_theme_font_size_override("font_size", 10)
	slot.add_child(num_label)

	return slot


func _create_skill_button(key: String, skill_name: String, active: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(60, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BUTTON_BG if active else Color(0.08, 0.07, 0.1, 1.0)
	sb.border_color = COLOR_BUTTON_BORDER if active else Color(0.25, 0.2, 0.15, 1.0)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", sb)

	var key_label := Label.new()
	key_label.text = key
	key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key_label.position = Vector2(4, 2)
	key_label.add_theme_color_override("font_color", COLOR_BORDER if active else COLOR_TEXT_DIM)
	key_label.add_theme_font_size_override("font_size", 11)
	panel.add_child(key_label)

	if skill_name != "":
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = skill_name
		name_label.set_anchors_preset(Control.PRESET_CENTER)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", COLOR_TEXT if active else COLOR_TEXT_DIM)
		name_label.add_theme_font_size_override("font_size", 13)
		panel.add_child(name_label)

	var cd_label := Label.new()
	cd_label.name = "CDLabel"
	cd_label.text = ""
	cd_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cd_label.position = Vector2(-24, -20)
	cd_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3, 1.0))
	cd_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(cd_label)

	return panel


func set_observed_peer(peer_id: int) -> void:
	var safe_peer_id: int = maxi(peer_id, 0)
	if _observed_peer_id == safe_peer_id:
		return
	_observed_peer_id = safe_peer_id
	_last_inventory_signature = ""
	if _is_observing_remote():
		_destroy_mode = false
		_destroy_hover_index = -1
		if _hero_ctrl != null and _hero_ctrl.has_method("set_destroy_cursor_mode"):
			_hero_ctrl.call("set_destroy_cursor_mode", false)
	_sync_destroy_hover_cursor()
	_update_destroy_visual()
	_update_shop_info()


func _update_network_view_state() -> void:
	if _net_ctrl == null:
		_net_ctrl = get_node_or_null(net_session_controller_path)
	if _net_ctrl == null:
		_self_peer_id = 0
		_observed_remote_hero_state.clear()
		_observed_remote_equipment_state.clear()
		return
	if _net_ctrl.has_method("get_ui_self_peer_id"):
		_self_peer_id = int(_net_ctrl.call("get_ui_self_peer_id"))
	else:
		_self_peer_id = 0

	if _observed_peer_id > 0 and _self_peer_id > 0 and _observed_peer_id == _self_peer_id:
		set_observed_peer(0)

	if _observed_peer_id <= 0:
		_observed_remote_hero_state.clear()
		_observed_remote_equipment_state.clear()
		return

	_observed_remote_hero_state = {}
	_observed_remote_equipment_state = {}
	if _net_ctrl.has_method("get_ui_peer_hero_state"):
		var hero_state_variant: Variant = _net_ctrl.call("get_ui_peer_hero_state", _observed_peer_id)
		if hero_state_variant is Dictionary:
			_observed_remote_hero_state = hero_state_variant
	if _net_ctrl.has_method("get_ui_peer_equipment_state"):
		var equip_state_variant: Variant = _net_ctrl.call("get_ui_peer_equipment_state", _observed_peer_id)
		if equip_state_variant is Dictionary:
			_observed_remote_equipment_state = equip_state_variant
	if _observed_remote_hero_state.is_empty() and _observed_remote_equipment_state.is_empty():
		set_observed_peer(0)


func _is_observing_remote() -> bool:
	return _observed_peer_id > 0 and (_self_peer_id <= 0 or _observed_peer_id != _self_peer_id)


func _get_observed_hero_state() -> Dictionary:
	if not _is_observing_remote():
		return {}
	return _observed_remote_hero_state


func _get_observed_equipment_state() -> Dictionary:
	if not _is_observing_remote():
		return {}
	return _observed_remote_equipment_state


func _skill_name_from_id(skill_id: int, is_q: bool) -> String:
	match skill_id:
		101:
			return "闪现"
		102:
			return "急速"
		201:
			return "战术翻滚"
		202:
			return "火力全开"
		_:
			if is_q:
				return "Q技能"
			return "W技能"


func _update_skill_name_labels() -> void:
	if _is_observing_remote():
		var hero_state: Dictionary = _get_observed_hero_state()
		if hero_state.is_empty():
			return
		if _q_skill_name_label != null:
			var q_name: String = str(hero_state.get("skill_q_name", "")).strip_edges()
			if q_name.is_empty():
				q_name = _skill_name_from_id(int(hero_state.get("skill_q_id", 0)), true)
			_q_skill_name_label.text = q_name
		if _w_skill_name_label != null:
			var w_name: String = str(hero_state.get("skill_w_name", "")).strip_edges()
			if w_name.is_empty():
				w_name = _skill_name_from_id(int(hero_state.get("skill_w_id", 0)), false)
			_w_skill_name_label.text = w_name
		return

	if _hero_ctrl == null:
		return
	if _q_skill_name_label != null:
		var q_name = _hero_ctrl.get("skill_q_name")
		if q_name != null:
			_q_skill_name_label.text = str(q_name)
	if _w_skill_name_label != null:
		var w_name = _hero_ctrl.get("skill_w_name")
		if w_name != null:
			_w_skill_name_label.text = str(w_name)


func _update_hero_info() -> void:
	if _is_observing_remote():
		_update_remote_hero_info()
		return
	if _hero_ctrl == null or _hero_hp_bar == null:
		return
	if _hero_name_label != null:
		var local_profile: String = str(_hero_ctrl.get("hero_profile"))
		if local_profile.strip_edges().is_empty():
			local_profile = "本地"
		_hero_name_label.text = "你自己 · %s" % local_profile

	var current_hp = _hero_ctrl.get("_current_hp")
	var max_hp = _hero_ctrl.get("max_hp")
	if current_hp == null or max_hp == null:
		return

	var ratio := float(current_hp) / float(max_hp) * 100.0
	_hero_hp_bar.value = ratio
	_hero_hp_label.text = "%d / %d" % [current_hp, max_hp]

	var fill_sb := _hero_hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_sb != null:
		fill_sb.bg_color = COLOR_HP_LOW.lerp(COLOR_HP_FULL, float(current_hp) / float(max_hp))

	var current_mp = _hero_ctrl.get("current_mana")
	var max_mp = _hero_ctrl.get("max_mana")
	if current_mp != null and max_mp != null and _hero_mp_bar != null and _hero_mp_label != null:
		var mp_max_value := maxi(int(max_mp), 1)
		var mp_ratio := float(current_mp) / float(mp_max_value) * 100.0
		_hero_mp_bar.value = mp_ratio
		_hero_mp_label.text = "%d / %d" % [current_mp, max_mp]

	var dmg = _hero_ctrl.get("damage_per_hit")
	if dmg != null and _atk_label != null:
		_atk_label.text = "攻击: %d" % dmg
	var str_val = _hero_ctrl.get("strength")
	var agi_val = _hero_ctrl.get("agility")
	var int_val = _hero_ctrl.get("intelligence")

	var hero_lv = _hero_ctrl.get("hero_level")
	var str_base = _hero_ctrl.get("strength_base")
	var agi_base = _hero_ctrl.get("agility_base")
	var int_base = _hero_ctrl.get("intelligence_base")
	var str_growth = _hero_ctrl.get("strength_growth")
	var agi_growth = _hero_ctrl.get("agility_growth")
	var int_growth = _hero_ctrl.get("intelligence_growth")
	var has_growth_data: bool = false
	var natural_str: int = 0
	var natural_agi: int = 0
	var natural_int: int = 0
	if hero_lv != null and str_base != null and agi_base != null and int_base != null and str_growth != null and agi_growth != null and int_growth != null:
		var lv_i: int = maxi(int(hero_lv), 1)
		natural_str = int(round(float(str_base) + float(str_growth) * float(lv_i - 1)))
		natural_agi = int(round(float(agi_base) + float(agi_growth) * float(lv_i - 1)))
		natural_int = int(round(float(int_base) + float(int_growth) * float(lv_i - 1)))
		has_growth_data = true

	var attack_range = _hero_ctrl.get("attack_range")
	var attack_speed = _hero_ctrl.get("attack_speed")
	var attack_interval = _hero_ctrl.get("attack_interval")
	var cooldown_reduction_percent_total = _hero_ctrl.get("cooldown_reduction_percent_total")
	var passive_skill_name = _hero_ctrl.get("skill_passive_name")
	var physical_crit_chance = _hero_ctrl.get("physical_crit_chance")
	var physical_crit_multiplier = _hero_ctrl.get("physical_crit_multiplier")
	var spell_crit_chance = _hero_ctrl.get("spell_crit_chance")
	var spell_crit_multiplier = _hero_ctrl.get("spell_crit_multiplier")
	var primary_attr_name_var = _hero_ctrl.get("primary_attribute")
	var primary_attr_name: String = "敏捷"
	if primary_attr_name_var != null:
		primary_attr_name = str(primary_attr_name_var)
	var primary_attr_value: int = 0
	match primary_attr_name:
		"力量":
			if str_val != null:
				primary_attr_value = int(str_val)
		"智力":
			if int_val != null:
				primary_attr_value = int(int_val)
		_:
			if agi_val != null:
				primary_attr_value = int(agi_val)

	if _atk_label != null:
		var range_text: String = "-"
		var speed_text: String = "-"
		var interval_text: String = "-"
		var ias_text: String = "-"
		var cdr_text: String = "-"
		var dmg_text: String = "-"
		var base_damage_text: String = "-"
		var equip_damage_text: String = "0"
		var base_damage_flat = _hero_ctrl.get("base_damage_flat")
		var equip_damage_bonus = _hero_ctrl.get("_equip_damage_bonus")
		var attack_speed_percent_total = _hero_ctrl.get("attack_speed_percent_total")
		if attack_range != null:
			range_text = str(int(round(float(attack_range))))
		if attack_speed != null:
			speed_text = "%.2f" % float(attack_speed)
		if attack_interval != null:
			interval_text = "%.2f" % float(attack_interval)
		if attack_speed_percent_total != null:
			ias_text = "%.1f%%" % float(attack_speed_percent_total)
		if cooldown_reduction_percent_total != null:
			cdr_text = "%.1f%%" % float(cooldown_reduction_percent_total)
		if dmg != null:
			dmg_text = str(int(dmg))
		if base_damage_flat != null:
			base_damage_text = str(int(base_damage_flat))
		if equip_damage_bonus != null:
			equip_damage_text = str(int(equip_damage_bonus))
		var pcrit_text: String = "-"
		var pcrit_mul_text: String = "-"
		var passive_text: String = "-"
		if physical_crit_chance != null:
			pcrit_text = "%.1f%%" % float(physical_crit_chance)
		if physical_crit_multiplier != null:
			pcrit_mul_text = "%.2fx" % float(physical_crit_multiplier)
		if passive_skill_name != null:
			passive_text = str(passive_skill_name)
		var atk_tip := "主属性: %s (%d)\n基础攻击: %s\n装备攻击加成: +%s\n最终攻击: %s\n攻速加成(IAS): %s\n攻击速度: %s 次/秒\n攻击间隔: %s 秒\n攻击范围: %s\n冷却减免(CDR): %s\n物理暴击率: %s\n物理暴击倍率: %s\n被动技能: %s" % [primary_attr_name, primary_attr_value, base_damage_text, equip_damage_text, dmg_text, ias_text, speed_text, interval_text, range_text, cdr_text, pcrit_text, pcrit_mul_text, passive_text]
		_set_tooltip_if_changed(_atk_label, atk_tip)
	if _atk_speed_label != null and attack_speed != null:
		_atk_speed_label.text = "攻速: %.2f" % float(attack_speed)
	if _atk_interval_label != null and attack_interval != null:
		_atk_interval_label.text = "攻间隔: %.2f" % float(attack_interval)
	if _atk_range_label != null and attack_range != null:
		_atk_range_label.text = "攻距: %d" % int(round(float(attack_range)))
	if _cdr_label != null and cooldown_reduction_percent_total != null:
		_cdr_label.text = "冷却减免: %.1f%%" % float(cooldown_reduction_percent_total)
		_set_tooltip_if_changed(_cdr_label, "缩短技能冷却时间（当前作用于 Q/W）。上限 80%。")
	if _phys_crit_rate_label != null and physical_crit_chance != null:
		_phys_crit_rate_label.text = "物暴率: %.1f%%" % float(physical_crit_chance)
		_set_tooltip_if_changed(_phys_crit_rate_label, "普通攻击触发暴击的概率。")
	if _phys_crit_mul_label != null and physical_crit_multiplier != null:
		_phys_crit_mul_label.text = "物暴倍: %.2fx" % float(physical_crit_multiplier)
		_set_tooltip_if_changed(_phys_crit_mul_label, "普通攻击暴击时造成的伤害倍率。")
	if _spell_crit_rate_label != null and spell_crit_chance != null:
		_spell_crit_rate_label.text = "法暴率: %.1f%%" % float(spell_crit_chance)
		_set_tooltip_if_changed(_spell_crit_rate_label, "法术伤害触发暴击的概率（如Q、毒伤）。")
	if _spell_crit_mul_label != null and spell_crit_multiplier != null:
		_spell_crit_mul_label.text = "法暴倍: %.2fx" % float(spell_crit_multiplier)
		_set_tooltip_if_changed(_spell_crit_mul_label, "法术暴击时造成的伤害倍率。")
	var armor = _hero_ctrl.get("armor")
	if armor != null and _def_label != null:
		_def_label.text = "护甲: %.1f" % float(armor)
	var spd = _hero_ctrl.get("move_speed")
	if spd != null and _spd_label != null:
		_spd_label.text = "移速: %d" % int(spd)
	if _spd_label != null:
		_set_tooltip_if_changed(_spd_label, "冰封王座移速限制: 100 - 522")
	var hp_regen = _hero_ctrl.get("hp_regen_per_second")
	if hp_regen != null and _hp_regen_label != null:
		_hp_regen_label.text = "回血: %.2f/s" % float(hp_regen)
	var mp_regen = _hero_ctrl.get("mana_regen_per_second")
	if mp_regen != null and _mp_regen_label != null:
		_mp_regen_label.text = "回蓝: %.2f/s" % float(mp_regen)
	if str_val != null and _str_label != null:
		_str_label.text = "力量: %d" % int(str_val)
		var str_now: int = int(str_val)
		var str_hp_bonus: int = str_now * 25
		var str_regen_bonus: float = float(str_now) * 0.05
		var str_natural_text: String = "-"
		var str_equip_text: String = "-"
		if has_growth_data:
			str_natural_text = str(natural_str)
			str_equip_text = str(str_now - natural_str)
		var str_tip := "每点力量提供:\n+25 生命上限\n+0.05 生命回复/秒\n\n当前力量: %d\n自然成长: %s\n装备加成: %s\n力量提供生命: +%d\n力量提供回血: +%.2f/s" % [str_now, str_natural_text, str_equip_text, str_hp_bonus, str_regen_bonus]
		_set_tooltip_if_changed(_str_label, str_tip)
	if agi_val != null and _agi_label != null:
		_agi_label.text = "敏捷: %d" % int(agi_val)
		var agi_now: int = int(agi_val)
		var agi_ias_bonus: float = float(agi_now)
		var agi_armor_bonus: float = float(agi_now) * 0.14
		var agi_natural_text: String = "-"
		var agi_equip_text: String = "-"
		if has_growth_data:
			agi_natural_text = str(natural_agi)
			agi_equip_text = str(agi_now - natural_agi)
		var agi_tip := "每点敏捷提供:\n+1%% 攻速(IAS)\n+0.14 护甲\n\n当前敏捷: %d\n自然成长: %s\n装备加成: %s\n敏捷提供攻速: +%.1f%%\n敏捷提供护甲: +%.2f" % [agi_now, agi_natural_text, agi_equip_text, agi_ias_bonus, agi_armor_bonus]
		_set_tooltip_if_changed(_agi_label, agi_tip)
	if int_val != null and _int_label != null:
		_int_label.text = "智力: %d" % int(int_val)
		var int_now: int = int(int_val)
		var int_mp_bonus: int = int_now * 15
		var int_regen_bonus: float = float(int_now) * 0.05
		var int_natural_text: String = "-"
		var int_equip_text: String = "-"
		if has_growth_data:
			int_natural_text = str(natural_int)
			int_equip_text = str(int_now - natural_int)
		var int_tip := "每点智力提供:\n+15 法力上限\n+0.05 法力回复/秒\n\n当前智力: %d\n自然成长: %s\n装备加成: %s\n智力提供法力: +%d\n智力提供回蓝: +%.2f/s" % [int_now, int_natural_text, int_equip_text, int_mp_bonus, int_regen_bonus]
		_set_tooltip_if_changed(_int_label, int_tip)


func _update_remote_hero_info() -> void:
	var hero_state: Dictionary = _get_observed_hero_state()
	if hero_state.is_empty():
		return
	if _hero_hp_bar == null:
		return

	var current_hp: int = int(hero_state.get("hp", 0))
	var max_hp: int = maxi(int(hero_state.get("max_hp", 1)), 1)
	var hp_ratio: float = clampf(float(current_hp) / float(max_hp) * 100.0, 0.0, 100.0)
	_hero_hp_bar.value = hp_ratio
	if _hero_hp_label != null:
		_hero_hp_label.text = "%d / %d" % [current_hp, max_hp]

	var fill_sb := _hero_hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_sb != null:
		fill_sb.bg_color = COLOR_HP_LOW.lerp(COLOR_HP_FULL, float(current_hp) / float(max_hp))

	var current_mp: int = int(hero_state.get("mana", 0))
	var max_mp: int = maxi(int(hero_state.get("max_mana", 1)), 1)
	if _hero_mp_bar != null:
		_hero_mp_bar.value = clampf(float(current_mp) / float(max_mp) * 100.0, 0.0, 100.0)
	if _hero_mp_label != null:
		_hero_mp_label.text = "%d / %d" % [current_mp, max_mp]

	var profile_text: String = str(hero_state.get("hero_profile", ""))
	if profile_text.strip_edges().is_empty():
		profile_text = "远端英雄"
	if _hero_name_label != null:
		_hero_name_label.text = "玩家P%d · %s" % [_observed_peer_id, profile_text]

	if _atk_label != null:
		if hero_state.has("damage"):
			_atk_label.text = "攻击: %d" % int(hero_state.get("damage", 0))
		else:
			_atk_label.text = "攻击: -"
	if _def_label != null:
		if hero_state.has("armor"):
			_def_label.text = "护甲: %.1f" % float(hero_state.get("armor", 0.0))
		else:
			_def_label.text = "护甲: -"
	if _spd_label != null:
		if hero_state.has("move_speed"):
			_spd_label.text = "移速: %d" % int(round(float(hero_state.get("move_speed", 0.0))))
		else:
			_spd_label.text = "移速: -"

	if _atk_speed_label != null:
		if hero_state.has("attack_speed"):
			_atk_speed_label.text = "攻速: %.2f" % float(hero_state.get("attack_speed", 0.0))
		else:
			_atk_speed_label.text = "攻速: -"
	if _atk_interval_label != null:
		if hero_state.has("attack_interval"):
			_atk_interval_label.text = "攻间隔: %.2f" % float(hero_state.get("attack_interval", 0.0))
		else:
			_atk_interval_label.text = "攻间隔: -"
	if _atk_range_label != null:
		if hero_state.has("attack_range"):
			_atk_range_label.text = "攻距: %d" % int(round(float(hero_state.get("attack_range", 0.0))))
		else:
			_atk_range_label.text = "攻距: -"
	if _cdr_label != null:
		if hero_state.has("cooldown_reduction_percent_total"):
			_cdr_label.text = "冷却减免: %.1f%%" % float(hero_state.get("cooldown_reduction_percent_total", 0.0))
		else:
			_cdr_label.text = "冷却减免: -"
	if _phys_crit_rate_label != null:
		if hero_state.has("physical_crit_chance"):
			_phys_crit_rate_label.text = "物暴率: %.1f%%" % float(hero_state.get("physical_crit_chance", 0.0))
		else:
			_phys_crit_rate_label.text = "物暴率: -"
	if _phys_crit_mul_label != null:
		if hero_state.has("physical_crit_multiplier"):
			_phys_crit_mul_label.text = "物暴倍: %.2fx" % float(hero_state.get("physical_crit_multiplier", 0.0))
		else:
			_phys_crit_mul_label.text = "物暴倍: -"
	if _spell_crit_rate_label != null:
		if hero_state.has("spell_crit_chance"):
			_spell_crit_rate_label.text = "法暴率: %.1f%%" % float(hero_state.get("spell_crit_chance", 0.0))
		else:
			_spell_crit_rate_label.text = "法暴率: -"
	if _spell_crit_mul_label != null:
		if hero_state.has("spell_crit_multiplier"):
			_spell_crit_mul_label.text = "法暴倍: %.2fx" % float(hero_state.get("spell_crit_multiplier", 0.0))
		else:
			_spell_crit_mul_label.text = "法暴倍: -"

	if _hp_regen_label != null:
		if hero_state.has("hp_regen_per_second"):
			_hp_regen_label.text = "回血: %.2f/s" % float(hero_state.get("hp_regen_per_second", 0.0))
		else:
			_hp_regen_label.text = "回血: -"
	if _mp_regen_label != null:
		if hero_state.has("mana_regen_per_second"):
			_mp_regen_label.text = "回蓝: %.2f/s" % float(hero_state.get("mana_regen_per_second", 0.0))
		else:
			_mp_regen_label.text = "回蓝: -"
	if _str_label != null:
		if hero_state.has("strength"):
			_str_label.text = "力量: %d" % int(hero_state.get("strength", 0))
		else:
			_str_label.text = "力量: -"
	if _agi_label != null:
		if hero_state.has("agility"):
			_agi_label.text = "敏捷: %d" % int(hero_state.get("agility", 0))
		else:
			_agi_label.text = "敏捷: -"
	if _int_label != null:
		if hero_state.has("intelligence"):
			_int_label.text = "智力: %d" % int(hero_state.get("intelligence", 0))
		else:
			_int_label.text = "智力: -"


func _update_boss_info() -> void:
	if _enemy_ai == null or _boss_hp_bar == null:
		return

	var current_hp = _enemy_ai.get("_current_hp")
	var max_hp = _enemy_ai.get("max_hp")
	if current_hp == null or max_hp == null:
		return

	var ratio := float(current_hp) / float(max_hp) * 100.0
	_boss_hp_bar.value = ratio
	_boss_hp_label.text = "%d / %d" % [current_hp, max_hp]


func _update_flash_cd() -> void:
	if _flash_cd_label == null:
		return
	if _is_observing_remote():
		var hero_state: Dictionary = _get_observed_hero_state()
		if hero_state.is_empty():
			_flash_cd_label.text = ""
			return
		var remote_cd: float = float(hero_state.get("flash_cd", 0.0))
		if remote_cd > 0.0:
			_flash_cd_label.text = "%.1f" % remote_cd
		else:
			_flash_cd_label.text = ""
		return
	if _hero_ctrl == null:
		return

	var cd = _hero_ctrl.get("_flash_cooldown")
	if cd == null:
		return

	if cd > 0.0:
		_flash_cd_label.text = "%.1f" % cd
	else:
		_flash_cd_label.text = ""


func _update_haste_cd() -> void:
	if _haste_cd_label == null:
		return
	if _is_observing_remote():
		var hero_state: Dictionary = _get_observed_hero_state()
		if hero_state.is_empty():
			_haste_cd_label.text = ""
			return
		var haste_active: bool = bool(hero_state.get("haste_active", false))
		var haste_left: float = float(hero_state.get("haste_left", 0.0))
		var haste_cd: float = float(hero_state.get("haste_cd", 0.0))
		if haste_active and haste_left > 0.0:
			_haste_cd_label.text = "↑%.1f" % haste_left
		elif haste_cd > 0.0:
			_haste_cd_label.text = "%.1f" % haste_cd
		else:
			_haste_cd_label.text = ""
		return
	if _hero_ctrl == null:
		return

	var haste_cd = _hero_ctrl.get("_haste_cooldown")
	var haste_active = _hero_ctrl.get("_haste_active")
	var haste_left = _hero_ctrl.get("_haste_time_left")
	if haste_active == true and haste_left != null and float(haste_left) > 0.0:
		_haste_cd_label.text = "↑%.1f" % float(haste_left)
	elif haste_cd != null and float(haste_cd) > 0.0:
		_haste_cd_label.text = "%.1f" % float(haste_cd)
	else:
		_haste_cd_label.text = ""


func _check_shop_click() -> void:
	if _hero_ctrl == null:
		return
	var clicked = _hero_ctrl.get("shop_clicked")
	if clicked == true:
		_hero_ctrl.set("shop_clicked", false)
		set_observed_peer(0)
		_toggle_shop()


func _toggle_shop() -> void:
	_shop_visible = not _shop_visible
	if _shop_panel:
		_shop_panel.visible = _shop_visible
		if _shop_visible:
			_update_shop_info()


func _build_shop_panel(root: Control) -> void:
	_shop_panel = Panel.new()
	_shop_panel.name = "ShopPanel"
	_shop_panel.visible = false
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.custom_minimum_size = Vector2(820, 520)
	_shop_panel.offset_left = -410
	_shop_panel.offset_right = 410
	_shop_panel.offset_top = -260
	_shop_panel.offset_bottom = 260
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.09, 0.97)
	sb.border_color = COLOR_BORDER
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	_shop_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_shop_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 14
	vbox.offset_right = -14
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 8)
	_shop_panel.add_child(vbox)

	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(title_hbox)
	var title := Label.new()
	title.text = "巫毒商店 - 肉鸽地牢"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", COLOR_BORDER)
	title.add_theme_font_size_override("font_size", 20)
	title_hbox.add_child(title)
	var close_btn := Button.new()
	close_btn.text = " X "
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_toggle_shop)
	title_hbox.add_child(close_btn)

	var info_hbox := HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(info_hbox)

	_shop_level_label = Label.new()
	_shop_level_label.add_theme_color_override("font_color", COLOR_BORDER)
	_shop_level_label.add_theme_font_size_override("font_size", 16)
	info_hbox.add_child(_shop_level_label)

	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	_gold_label.add_theme_font_size_override("font_size", 16)
	info_hbox.add_child(_gold_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_hbox.add_child(spacer)

	_upgrade_btn = Button.new()
	_upgrade_btn.add_theme_font_size_override("font_size", 13)
	_upgrade_btn.pressed.connect(_on_upgrade_shop)
	info_hbox.add_child(_upgrade_btn)

	_refresh_btn = Button.new()
	_refresh_btn.add_theme_font_size_override("font_size", 13)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	info_hbox.add_child(_refresh_btn)

	_update_shop_info()

	var sep := HSeparator.new()
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = COLOR_BORDER_DARK
	sep_sb.content_margin_top = 1
	sep_sb.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_offered_grid = GridContainer.new()
	_offered_grid.columns = 5
	_offered_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offered_grid.add_theme_constant_override("h_separation", 8)
	_offered_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_offered_grid)

	_roll_shop_items()
	_populate_offered_items()


func _get_item_level(item: Dictionary) -> int:
	var stat: String = item["stat"]
	if stat.begins_with("Lv"):
		var space_idx := stat.find(" ")
		if space_idx > 2:
			return int(stat.substr(2, space_idx - 2))
	return 1


func _update_shop_info() -> void:
	var display_shop_level: int = _shop_level
	var display_gold: int = _gold
	var is_remote_view: bool = _is_observing_remote()
	if is_remote_view:
		var eq_state: Dictionary = _get_observed_equipment_state()
		if not eq_state.is_empty():
			display_shop_level = maxi(int(eq_state.get("shop_level", _shop_level)), 1)
			display_gold = int(eq_state.get("gold", _gold))
	if _shop_level_label:
		var stars := ""
		for i in range(7):
			stars += "★" if i < display_shop_level else "☆"
		var owner_text: String = "（玩家P%d）" % _observed_peer_id if is_remote_view else ""
		_shop_level_label.text = "商店等级: %s Lv%d %s" % [stars, display_shop_level, owner_text]
	if _gold_label:
		_gold_label.text = "金币: %d" % display_gold
	if _upgrade_btn:
		if is_remote_view:
			_upgrade_btn.text = "观战中"
			_upgrade_btn.disabled = true
		elif _shop_level >= 7:
			_upgrade_btn.text = "已满级"
			_upgrade_btn.disabled = true
		else:
			var cost: int = SHOP_UPGRADE_COST[_shop_level]
			_upgrade_btn.text = "升级商店 (%d金)" % cost
			_upgrade_btn.disabled = _gold < cost
	if _refresh_btn:
		if is_remote_view:
			_refresh_btn.text = "观战中"
			_refresh_btn.disabled = true
		else:
			_refresh_btn.text = "刷新商品 (%d金)" % SHOP_REFRESH_COST
			_refresh_btn.disabled = _gold < SHOP_REFRESH_COST


func _roll_shop_items() -> void:
	_shop_offered.clear()
	var count: int = SHOP_ITEM_COUNT[_shop_level]
	var weights: Dictionary = LEVEL_WEIGHTS[_shop_level]
	var total_weight := 0
	for w in weights.values():
		total_weight += w

	for _n in range(count):
		var rolled_level := 1
		var roll := randi() % total_weight
		var accum := 0
		for lv in weights:
			accum += weights[lv]
			if roll < accum:
				rolled_level = lv
				break

		var candidates: Array[int] = []
		for i in range(ITEM_DB.size()):
			if _get_item_level(ITEM_DB[i]) == rolled_level and i not in _shop_offered:
				candidates.append(i)

		if candidates.is_empty():
			for i in range(ITEM_DB.size()):
				if _get_item_level(ITEM_DB[i]) <= rolled_level and i not in _shop_offered:
					candidates.append(i)

		if not candidates.is_empty():
			_shop_offered.append(candidates[randi() % candidates.size()])


func _populate_offered_items() -> void:
	for child in _offered_grid.get_children():
		child.queue_free()
	for idx in _shop_offered:
		var item: Dictionary = ITEM_DB[idx]
		var card := _create_shop_item(item, idx)
		_offered_grid.add_child(card)


func _on_refresh_pressed() -> void:
	if _is_observing_remote():
		return
	if _gold < SHOP_REFRESH_COST:
		return
	_gold -= SHOP_REFRESH_COST
	_roll_shop_items()
	_populate_offered_items()
	_update_shop_info()


func _on_upgrade_shop() -> void:
	if _is_observing_remote():
		return
	if _shop_level >= 7:
		return
	var cost: int = SHOP_UPGRADE_COST[_shop_level]
	if _gold < cost:
		return
	_gold -= cost
	_shop_level += 1
	_roll_shop_items()
	_populate_offered_items()
	_update_shop_info()


func _get_build_color(build_name: String) -> Color:
	match build_name:
		"初始": return Color(0.6, 0.8, 0.6, 1.0)
		"过渡": return Color(0.7, 0.7, 0.7, 1.0)
		"摧毁": return Color(0.9, 0.3, 0.9, 1.0)
		"贷款": return Color(1.0, 0.85, 0.2, 1.0)
		"三月": return Color(0.5, 0.8, 1.0, 1.0)
		"自动": return Color(0.6, 0.6, 0.6, 1.0)
		"战旗": return Color(0.2, 0.9, 0.5, 1.0)
		"结算": return Color(0.9, 0.6, 0.2, 1.0)
		"充能": return Color(0.3, 0.7, 1.0, 1.0)
		"咒文": return Color(0.7, 0.4, 1.0, 1.0)
		"火花": return Color(1.0, 0.4, 0.2, 1.0)
		"特摧": return Color(1.0, 0.2, 0.6, 1.0)
		"硬币": return Color(1.0, 0.9, 0.3, 1.0)
		"诅咒": return Color(0.8, 0.2, 0.2, 1.0)
		"消耗": return Color(0.4, 0.8, 0.8, 1.0)
		"配件": return Color(0.8, 0.6, 0.3, 1.0)
		"后期": return Color(1.0, 0.3, 0.3, 1.0)
		_: return COLOR_TEXT


func _build_shop_item_tooltip(data: Dictionary, cost: int) -> String:
	var level: int = _get_item_level(data)
	var build_name: String = str(data.get("build", "未知"))
	var item_name: String = str(data.get("name", "未知装备"))
	var stat_text: String = str(data.get("stat", ""))
	return "【%s】%s\n等级: Lv%d\n价格: %d金\n\n%s" % [build_name, item_name, level, cost, stat_text]


func _create_shop_item(data: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(148, 130)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.1, 0.08, 0.16, 1.0)
	ssb.border_color = COLOR_BUTTON_BORDER
	ssb.set_border_width_all(2)
	ssb.corner_radius_top_left = 4
	ssb.corner_radius_top_right = 4
	ssb.corner_radius_bottom_left = 4
	ssb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", ssb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var build_label := Label.new()
	build_label.text = "[%s]" % data["build"]
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_label.add_theme_color_override("font_color", _get_build_color(data["build"]))
	build_label.add_theme_font_size_override("font_size", 9)
	build_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(build_label)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_center)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(42, 42)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := load(P + data["icon"]) as Texture2D
	if tex:
		icon.texture = tex
	icon_center.add_child(icon)

	var name_label := Label.new()
	name_label.text = "%s·%s" % [data["build"], data["name"]]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", _get_build_color(data["build"]))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var stat_label := Label.new()
	stat_label.text = data["stat"]
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
	stat_label.add_theme_font_size_override("font_size", 10)
	stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stat_label)

	var item_lv := _get_item_level(data)
	var cost: int = ITEM_COST.get(item_lv, 50)
	var tooltip_text: String = _build_shop_item_tooltip(data, cost)
	panel.tooltip_text = tooltip_text

	var buy_btn := Button.new()
	buy_btn.text = "购买 (%d金)" % cost
	buy_btn.add_theme_font_size_override("font_size", 11)
	buy_btn.tooltip_text = tooltip_text
	buy_btn.pressed.connect(_on_buy_item.bind(index))
	vbox.add_child(buy_btn)

	return panel


func _on_buy_item(index: int) -> void:
	if _is_observing_remote():
		return
	if _hero_ctrl == null:
		return
	var inv: Array = _hero_ctrl.get("inventory")
	if inv == null:
		return
	if inv.size() >= 6:
		return
	var item_data: Dictionary = ITEM_DB[index]
	var item_lv := _get_item_level(item_data)
	var cost: int = ITEM_COST.get(item_lv, 50)
	if _gold < cost:
		return
	_gold -= cost
	inv.append(index)
	_shop_offered.erase(index)
	_try_synthesize()
	_refresh_inventory()
	_populate_offered_items()
	_update_shop_info()


func _find_item_index_by_name(item_name: String) -> int:
	for i in range(ITEM_DB.size()):
		if ITEM_DB[i]["name"] == item_name:
			return i
	return -1


func _sum_regex_int(text: String, pattern: String) -> int:
	var regex := RegEx.new()
	var compile_err: int = regex.compile(pattern)
	if compile_err != OK:
		return 0
	var total: int = 0
	for match_variant in regex.search_all(text):
		var match := match_variant as RegExMatch
		if match == null:
			continue
		var value_text: String = match.get_string(1)
		if value_text != "":
			total += int(value_text)
	return total


func _parse_item_bonus(item_data: Dictionary) -> Dictionary:
	var stat_text: String = str(item_data.get("stat", ""))
	var result: Dictionary = {
		"strength": 0,
		"agility": 0,
		"intelligence": 0,
		"hp": 0,
		"mana": 0,
		"damage": 0,
		"armor": 0.0,
		"attack_speed_percent": 0.0,
		"move_speed": 0.0,
		"cooldown_reduction_percent": 0.0,
		"physical_crit_chance": 0.0,
		"physical_crit_multiplier": 0.0,
		"spell_crit_chance": 0.0,
		"spell_crit_multiplier": 0.0
	}

	var all_attr: int = _sum_regex_int(stat_text, "\\+(\\d+)全属性")
	result["strength"] = int(result["strength"]) + all_attr
	result["agility"] = int(result["agility"]) + all_attr
	result["intelligence"] = int(result["intelligence"]) + all_attr

	result["strength"] = int(result["strength"]) + _sum_regex_int(stat_text, "\\+(\\d+)力量")
	result["agility"] = int(result["agility"]) + _sum_regex_int(stat_text, "\\+(\\d+)敏捷")
	result["agility"] = int(result["agility"]) + _sum_regex_int(stat_text, "\\+(\\d+)敏(?!捷)")
	result["intelligence"] = int(result["intelligence"]) + _sum_regex_int(stat_text, "\\+(\\d+)智力")
	result["intelligence"] = int(result["intelligence"]) + _sum_regex_int(stat_text, "\\+(\\d+)智(?!力)")

	result["hp"] = int(result["hp"]) + _sum_regex_int(stat_text, "\\+(\\d+)生命")
	result["hp"] = int(result["hp"]) + _sum_regex_int(stat_text, "\\+(\\d+)[Hh][Pp]")
	result["mana"] = int(result["mana"]) + _sum_regex_int(stat_text, "\\+(\\d+)(?:法力|魔法|蓝量|MP)")
	result["damage"] = int(result["damage"]) + _sum_regex_int(stat_text, "\\+(\\d+)攻击(?:力)?")
	result["armor"] = float(result["armor"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)护甲"))
	result["attack_speed_percent"] = float(result["attack_speed_percent"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%攻速"))
	result["attack_speed_percent"] = float(result["attack_speed_percent"]) + float(_sum_regex_int(stat_text, "攻速\\+(\\d+)%"))
	result["move_speed"] = float(result["move_speed"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)移速"))
	result["move_speed"] = float(result["move_speed"]) + float(_sum_regex_int(stat_text, "移速\\+(\\d+)"))
	result["cooldown_reduction_percent"] = float(result["cooldown_reduction_percent"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%冷却减免"))
	result["cooldown_reduction_percent"] = float(result["cooldown_reduction_percent"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%冷却缩减"))
	result["cooldown_reduction_percent"] = float(result["cooldown_reduction_percent"]) + float(_sum_regex_int(stat_text, "冷却减免\\+(\\d+)%"))
	result["cooldown_reduction_percent"] = float(result["cooldown_reduction_percent"]) + float(_sum_regex_int(stat_text, "冷却缩减\\+(\\d+)%"))
	result["cooldown_reduction_percent"] = float(result["cooldown_reduction_percent"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%[Cc][Dd][Rr]"))
	result["cooldown_reduction_percent"] = float(result["cooldown_reduction_percent"]) + float(_sum_regex_int(stat_text, "[Cc][Dd][Rr]\\+(\\d+)%"))
	result["physical_crit_chance"] = float(result["physical_crit_chance"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%暴击率"))
	result["physical_crit_chance"] = float(result["physical_crit_chance"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%暴击(?!率|伤害|倍率)"))
	result["physical_crit_multiplier"] = float(result["physical_crit_multiplier"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%(?:暴击伤害|暴击倍率)"))
	result["spell_crit_chance"] = float(result["spell_crit_chance"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%法术暴击率"))
	result["spell_crit_chance"] = float(result["spell_crit_chance"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%法暴率?"))
	result["spell_crit_multiplier"] = float(result["spell_crit_multiplier"]) + float(_sum_regex_int(stat_text, "\\+(\\d+)%(?:法术暴击伤害|法术暴击倍率|法暴伤害|法暴倍率)"))
	return result


func _calculate_inventory_bonuses(inv: Array) -> Dictionary:
	var total: Dictionary = {
		"strength": 0,
		"agility": 0,
		"intelligence": 0,
		"hp": 0,
		"mana": 0,
		"damage": 0,
		"armor": 0.0,
		"attack_speed_percent": 0.0,
		"move_speed": 0.0,
		"cooldown_reduction_percent": 0.0,
		"physical_crit_chance": 0.0,
		"physical_crit_multiplier": 0.0,
		"spell_crit_chance": 0.0,
		"spell_crit_multiplier": 0.0
	}
	for i in range(inv.size()):
		var item_idx: int = int(inv[i])
		if item_idx < 0 or item_idx >= ITEM_DB.size():
			continue
		var item_bonus: Dictionary = _parse_item_bonus(ITEM_DB[item_idx])
		total["strength"] = int(total["strength"]) + int(item_bonus.get("strength", 0))
		total["agility"] = int(total["agility"]) + int(item_bonus.get("agility", 0))
		total["intelligence"] = int(total["intelligence"]) + int(item_bonus.get("intelligence", 0))
		total["hp"] = int(total["hp"]) + int(item_bonus.get("hp", 0))
		total["mana"] = int(total["mana"]) + int(item_bonus.get("mana", 0))
		total["damage"] = int(total["damage"]) + int(item_bonus.get("damage", 0))
		total["armor"] = float(total["armor"]) + float(item_bonus.get("armor", 0.0))
		total["attack_speed_percent"] = float(total["attack_speed_percent"]) + float(item_bonus.get("attack_speed_percent", 0.0))
		total["move_speed"] = float(total["move_speed"]) + float(item_bonus.get("move_speed", 0.0))
		total["cooldown_reduction_percent"] = float(total["cooldown_reduction_percent"]) + float(item_bonus.get("cooldown_reduction_percent", 0.0))
		total["physical_crit_chance"] = float(total["physical_crit_chance"]) + float(item_bonus.get("physical_crit_chance", 0.0))
		total["physical_crit_multiplier"] = float(total["physical_crit_multiplier"]) + float(item_bonus.get("physical_crit_multiplier", 0.0))
		total["spell_crit_chance"] = float(total["spell_crit_chance"]) + float(item_bonus.get("spell_crit_chance", 0.0))
		total["spell_crit_multiplier"] = float(total["spell_crit_multiplier"]) + float(item_bonus.get("spell_crit_multiplier", 0.0))
	return total


func _apply_inventory_bonuses_to_hero() -> void:
	if _hero_ctrl == null:
		return
	var inv: Array = _hero_ctrl.get("inventory")
	if inv == null:
		return
	var total_bonus: Dictionary = _calculate_inventory_bonuses(inv)
	if _hero_ctrl.has_method("apply_equipment_bonuses"):
		_hero_ctrl.call("apply_equipment_bonuses", total_bonus)


func _try_synthesize() -> void:
	if _hero_ctrl == null:
		return
	var inv: Array = _hero_ctrl.get("inventory")
	if inv == null:
		return

	for r_idx in range(RECIPES.size()):
		var recipe: Dictionary = RECIPES[r_idx]
		var inputs: Dictionary = recipe["inputs"]
		var can_craft := true

		for item_name: String in inputs:
			var needed: int = int(inputs[item_name])
			var item_idx: int = _find_item_index_by_name(item_name)
			if item_idx < 0:
				can_craft = false
				break
			var count: int = 0
			for s in range(inv.size()):
				if int(inv[s]) == item_idx:
					count += 1
			if count < needed:
				can_craft = false
				break

		if not can_craft:
			continue

		for item_name: String in inputs:
			var needed: int = int(inputs[item_name])
			var item_idx: int = _find_item_index_by_name(item_name)
			for _i in range(needed):
				var pos: int = inv.find(item_idx)
				if pos >= 0:
					inv.remove_at(pos)

		var output_name: String = str(recipe["output"])
		var result_idx: int = _find_item_index_by_name(output_name)
		if result_idx >= 0:
			inv.append(result_idx)

		_try_synthesize()
		return


func _get_display_inventory() -> Array:
	var out: Array = []
	if _is_observing_remote():
		var eq_state: Dictionary = _get_observed_equipment_state()
		var inv_variant: Variant = eq_state.get("inventory", [])
		if inv_variant is Array:
			for value in inv_variant:
				out.append(int(value))
		return out
	if _hero_ctrl == null:
		return out
	var inv_variant: Variant = _hero_ctrl.get("inventory")
	if inv_variant is Array:
		for value in inv_variant:
			out.append(int(value))
	return out


func _build_inventory_signature(inv: Array) -> String:
	var parts: Array[String] = []
	for value in inv:
		parts.append(str(int(value)))
	var owner_key: int = 0
	if _is_observing_remote():
		owner_key = _observed_peer_id
	return "%d|%s" % [owner_key, ",".join(parts)]


func _refresh_inventory() -> void:
	var inv: Array = _get_display_inventory()
	var signature: String = _build_inventory_signature(inv)
	if signature == _last_inventory_signature:
		_sync_destroy_hover_cursor()
		return
	_last_inventory_signature = signature
	for i in range(6):
		if i < inv.size():
			var item_idx: int = inv[i]
			if item_idx >= 0 and item_idx < ITEM_DB.size():
				var icon_path: String = P + ITEM_DB[item_idx]["icon"]
				var tex := load(icon_path) as Texture2D
				if tex and i < _inventory_icons.size():
					_inventory_icons[i].texture = tex
					_inventory_icons[i].visible = true
				if i < _inventory_slots.size():
					_inventory_slots[i].tooltip_text = str(ITEM_DB[item_idx].get("name", ""))
			else:
				if i < _inventory_icons.size():
					_inventory_icons[i].visible = false
				if i < _inventory_slots.size():
					_inventory_slots[i].tooltip_text = ""
		else:
			if i < _inventory_icons.size():
				_inventory_icons[i].visible = false
			if i < _inventory_slots.size():
				_inventory_slots[i].tooltip_text = ""
	if not _is_observing_remote():
		_apply_inventory_bonuses_to_hero()
	_update_destroy_visual()
	_sync_destroy_hover_cursor()


func _is_inventory_slot_has_item(index: int) -> bool:
	var inv: Array = _get_display_inventory()
	return index >= 0 and index < inv.size()


func _find_hovered_inventory_index() -> int:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for i in range(_inventory_slots.size()):
		var slot: PanelContainer = _inventory_slots[i]
		if slot == null or not slot.visible:
			continue
		if slot.get_global_rect().has_point(mouse_pos):
			return i
	return -1


func _sync_destroy_hover_cursor() -> void:
	if _hero_ctrl == null or not _hero_ctrl.has_method("set_destroy_cursor_item_hover"):
		return
	if _is_observing_remote():
		_destroy_hover_index = -1
		_hero_ctrl.call("set_destroy_cursor_item_hover", false)
		return
	if not _destroy_mode:
		_destroy_hover_index = -1
		_hero_ctrl.call("set_destroy_cursor_item_hover", false)
		return
	if _destroy_hover_index < 0:
		_destroy_hover_index = _find_hovered_inventory_index()
	var hovering_item: bool = _is_inventory_slot_has_item(_destroy_hover_index)
	_hero_ctrl.call("set_destroy_cursor_item_hover", hovering_item)


func _on_inv_slot_mouse_entered(index: int) -> void:
	_destroy_hover_index = index
	_sync_destroy_hover_cursor()


func _on_inv_slot_mouse_exited(index: int) -> void:
	if _destroy_hover_index == index:
		_destroy_hover_index = -1
	_sync_destroy_hover_cursor()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_toggle_destroy_mode()


func _toggle_destroy_mode() -> void:
	if _is_observing_remote():
		return
	_destroy_mode = not _destroy_mode
	if _hero_ctrl != null and _hero_ctrl.has_method("set_destroy_cursor_mode"):
		_hero_ctrl.call("set_destroy_cursor_mode", _destroy_mode)
	_sync_destroy_hover_cursor()
	_update_destroy_visual()


func _update_destroy_visual() -> void:
	if _destroy_skill_panel:
		var dsb := StyleBoxFlat.new()
		if _destroy_mode:
			dsb.bg_color = Color(0.5, 0.1, 0.1, 1.0)
			dsb.border_color = Color(1.0, 0.2, 0.2, 1.0)
		else:
			dsb.bg_color = COLOR_BUTTON_BG
			dsb.border_color = COLOR_BUTTON_BORDER
		dsb.set_border_width_all(2)
		dsb.corner_radius_top_left = 3
		dsb.corner_radius_top_right = 3
		dsb.corner_radius_bottom_left = 3
		dsb.corner_radius_bottom_right = 3
		_destroy_skill_panel.add_theme_stylebox_override("panel", dsb)

	for i in range(_inventory_slots.size()):
		var slot := _inventory_slots[i]
		var ssb := StyleBoxFlat.new()
		var has_item := false
		if _hero_ctrl:
			var inv: Array = _hero_ctrl.get("inventory")
			if inv and i < inv.size():
				has_item = true
		if _destroy_mode and has_item:
			ssb.bg_color = Color(0.25, 0.05, 0.05, 1.0)
			ssb.border_color = Color(1.0, 0.2, 0.2, 0.8)
		else:
			ssb.bg_color = Color(0.06, 0.05, 0.09, 1.0)
			ssb.border_color = COLOR_BORDER_DARK
		ssb.set_border_width_all(1)
		ssb.corner_radius_top_left = 2
		ssb.corner_radius_top_right = 2
		ssb.corner_radius_bottom_left = 2
		ssb.corner_radius_bottom_right = 2
		slot.add_theme_stylebox_override("panel", ssb)


func _on_inv_slot_input(event: InputEvent, index: int) -> void:
	if _is_observing_remote():
		return
	if not _destroy_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_destroy_item(index)


func _destroy_item(index: int) -> void:
	if _is_observing_remote():
		return
	if _hero_ctrl == null:
		return
	var inv: Array = _hero_ctrl.get("inventory")
	if inv == null or index >= inv.size():
		return
	inv.remove_at(index)
	_refresh_inventory()
	_destroy_mode = false
	_destroy_hover_index = -1
	if _hero_ctrl != null and _hero_ctrl.has_method("set_destroy_cursor_mode"):
		_hero_ctrl.call("set_destroy_cursor_mode", false)
	_sync_destroy_hover_cursor()
	_update_destroy_visual()
