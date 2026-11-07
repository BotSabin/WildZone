extends RefCounted
## Static game data: characters, tools, animals, rocks, items, building recipes, levels.

const MAP_RADIUS: float = 130.0
const PLAYER_LIMIT: float = 138.0
const TRADER_POS: Vector3 = Vector3(6.0, 0.0, -2.2)
const CAMP_SAFE_RADIUS: float = 12.0
const DAY_LENGTH: float = 600.0
const MAX_LEVEL: int = 99
const MAX_TOOL_LEVEL: int = 3
const MAX_AMMO: int = 300
const MAX_MEDKITS: int = 5

# --------------------------------------------------
# CHARACTERS
# --------------------------------------------------
const CHARACTERS: Array = [
	{
		"name": "Hunter",
		"desc": "Sharpshooter with a scoped rifle: +25% rifle damage.",
		"jacket": Color(0.27, 0.36, 0.2), "shirt": Color(0.75, 0.68, 0.52),
		"pants": Color(0.32, 0.26, 0.18), "boots": Color(0.2, 0.13, 0.08),
		"hat": "ranger_hat", "hat_color": Color(0.38, 0.27, 0.15),
		"skin": Color(0.87, 0.68, 0.53), "hair": Color(0.25, 0.16, 0.09),
		"signature": "scope",
		"damage": 1.25, "speed": 1.0, "mine": 1.0, "chop": 1.0,
	},
	{
		"name": "Miner",
		"desc": "Lamp helmet and steel pick: mines 30% faster, finds bonus ore.",
		"jacket": Color(0.86, 0.47, 0.12), "shirt": Color(0.3, 0.32, 0.38),
		"pants": Color(0.2, 0.24, 0.34), "boots": Color(0.15, 0.12, 0.1),
		"hat": "helmet", "hat_color": Color(0.95, 0.78, 0.12),
		"skin": Color(0.8, 0.6, 0.45), "hair": Color(0.12, 0.1, 0.08),
		"signature": "lamp",
		"damage": 1.0, "speed": 1.0, "mine": 0.7, "chop": 1.0,
	},
	{
		"name": "Trapper",
		"desc": "Fur cape and skinning knife: +1 pelt from every animal.",
		"jacket": Color(0.46, 0.32, 0.19), "shirt": Color(0.6, 0.5, 0.36),
		"pants": Color(0.3, 0.24, 0.17), "boots": Color(0.24, 0.16, 0.1),
		"hat": "fur_hat", "hat_color": Color(0.6, 0.47, 0.33),
		"skin": Color(0.9, 0.72, 0.58), "hair": Color(0.55, 0.35, 0.18),
		"signature": "cape",
		"damage": 1.0, "speed": 1.0, "mine": 1.0, "chop": 1.0,
	},
	{
		"name": "Scout",
		"desc": "Light gear and binoculars: +15% movement speed.",
		"jacket": Color(0.2, 0.32, 0.46), "shirt": Color(0.85, 0.85, 0.8),
		"pants": Color(0.22, 0.24, 0.26), "boots": Color(0.12, 0.12, 0.13),
		"hat": "beret", "hat_color": Color(0.16, 0.42, 0.27),
		"skin": Color(0.7, 0.5, 0.38), "hair": Color(0.08, 0.06, 0.05),
		"signature": "binoculars",
		"damage": 1.0, "speed": 1.15, "mine": 1.0, "chop": 1.0,
	},
	{
		"name": "Lumberjack",
		"desc": "Big beard, bigger axe: +1 wood per chop and chops 30% faster.",
		"jacket": Color(0.68, 0.15, 0.12), "shirt": Color(0.2, 0.2, 0.22),
		"pants": Color(0.22, 0.27, 0.38), "boots": Color(0.25, 0.16, 0.09),
		"hat": "beanie", "hat_color": Color(0.2, 0.22, 0.25),
		"skin": Color(0.88, 0.66, 0.5), "hair": Color(0.45, 0.25, 0.1),
		"signature": "beard",
		"damage": 1.0, "speed": 1.0, "mine": 1.0, "chop": 0.7,
	},
]

# --------------------------------------------------
# TOOLS
# --------------------------------------------------
const TOOLS: Array = ["rifle", "pickaxe", "axe", "hammer"]
const TOOL_NAMES: Dictionary = {
	"rifle": ["", "Old Rifle", "Hunting Rifle", "Marksman Rifle"],
	"pickaxe": ["", "Iron Pickaxe", "Steel Pickaxe", "Gold-Tipped Pickaxe"],
	"axe": ["", "Hatchet", "Felling Axe", "Lumber Axe"],
	"hammer": ["", "Builder's Hammer", "Builder's Hammer", "Builder's Hammer"],
}
const RIFLE_DAMAGE: Array = [0.0, 25.0, 40.0, 60.0]

# --------------------------------------------------
# ITEMS
# --------------------------------------------------
const ITEMS: Dictionary = {
	"fur_rabbit": {"name": "Rabbit Fur", "price": 8},
	"fur_fox": {"name": "Fox Fur", "price": 16},
	"hide_deer": {"name": "Deer Hide", "price": 22},
	"hide_boar": {"name": "Boar Hide", "price": 26},
	"pelt_wolf": {"name": "Wolf Pelt", "price": 38},
	"pelt_bear": {"name": "Bear Pelt", "price": 95},
	"meat": {"name": "Raw Meat", "price": 4, "eat": 15},
	"wood": {"name": "Wood", "price": 2},
	"stone": {"name": "Stone", "price": 2},
	"iron": {"name": "Iron Ore", "price": 9},
	"gold": {"name": "Gold Nugget", "price": 28},
}

const ITEM_ORDER: Array = [
	"fur_rabbit", "fur_fox", "hide_deer", "hide_boar", "pelt_wolf", "pelt_bear",
	"meat", "wood", "stone", "iron", "gold",
]

## Materials are kept when you press "Sell loot" (you need them for building).
const MATERIALS: Array = ["wood", "stone", "iron"]

# --------------------------------------------------
# ANIMALS
# --------------------------------------------------
const ANIMAL_TYPES: Array = ["rabbit", "fox", "deer", "boar", "wolf", "bear"]

## behavior: passive = runs away, defensive = fights back when hurt,
## aggressive = hunts players inside "sense" range.
const ANIMALS: Dictionary = {
	"rabbit": {
		"name": "Rabbit", "hp": 15.0, "walk": 1.8, "run": 7.5, "radius": 0.35,
		"behavior": "passive", "sense": 9.0, "damage": 0.0, "attack_cd": 1.0,
		"loot": {"fur_rabbit": 1, "meat": 1}, "count": 9, "min_dist": 20.0, "xp": 8,
		"color": Color(0.6, 0.52, 0.42), "belly": Color(0.9, 0.86, 0.78),
	},
	"fox": {
		"name": "Fox", "hp": 30.0, "walk": 2.4, "run": 8.0, "radius": 0.5,
		"behavior": "passive", "sense": 13.0, "damage": 0.0, "attack_cd": 1.0,
		"loot": {"fur_fox": 1, "meat": 1}, "count": 5, "min_dist": 25.0, "xp": 14,
		"color": Color(0.86, 0.43, 0.14), "belly": Color(0.96, 0.94, 0.88),
	},
	"deer": {
		"name": "Deer", "hp": 60.0, "walk": 2.0, "run": 9.0, "radius": 0.9,
		"behavior": "passive", "sense": 18.0, "damage": 0.0, "attack_cd": 1.0,
		"loot": {"hide_deer": 1, "meat": 3}, "count": 7, "min_dist": 25.0, "xp": 24,
		"color": Color(0.6, 0.4, 0.22), "belly": Color(0.88, 0.8, 0.66),
	},
	"boar": {
		"name": "Boar", "hp": 90.0, "walk": 1.8, "run": 7.8, "radius": 0.8,
		"behavior": "defensive", "sense": 6.0, "damage": 14.0, "attack_cd": 1.3,
		"loot": {"hide_boar": 1, "meat": 3}, "count": 4, "min_dist": 35.0, "xp": 34,
		"color": Color(0.33, 0.26, 0.21), "belly": Color(0.42, 0.34, 0.28),
	},
	"wolf": {
		"name": "Wolf", "hp": 70.0, "walk": 2.4, "run": 8.3, "radius": 0.7,
		"behavior": "aggressive", "sense": 20.0, "damage": 12.0, "attack_cd": 1.1,
		"loot": {"pelt_wolf": 1, "meat": 2}, "count": 4, "min_dist": 55.0, "xp": 45,
		"color": Color(0.52, 0.52, 0.54), "belly": Color(0.82, 0.82, 0.8),
	},
	"bear": {
		"name": "Bear", "hp": 240.0, "walk": 1.7, "run": 7.2, "radius": 1.25,
		"behavior": "aggressive", "sense": 14.0, "damage": 28.0, "attack_cd": 1.7,
		"loot": {"pelt_bear": 1, "meat": 6}, "count": 2, "min_dist": 70.0, "xp": 120,
		"color": Color(0.32, 0.21, 0.13), "belly": Color(0.4, 0.28, 0.18),
	},
}

# --------------------------------------------------
# ROCKS & TREES
# --------------------------------------------------
const ROCKS: Dictionary = {
	"stone": {"name": "Stone", "item": "stone", "amount": 5, "radius": 1.3, "xp": 4,
		"color": Color(0.47, 0.47, 0.49), "ore": Color(0.55, 0.55, 0.57), "glow": 0.0},
	"iron": {"name": "Iron Vein", "item": "iron", "amount": 4, "radius": 1.4, "xp": 8,
		"color": Color(0.4, 0.38, 0.37), "ore": Color(0.75, 0.38, 0.18), "glow": 0.0},
	"gold": {"name": "Gold Vein", "item": "gold", "amount": 3, "radius": 1.4, "xp": 15,
		"color": Color(0.36, 0.35, 0.36), "ore": Color(1.0, 0.8, 0.2), "glow": 0.6},
}
const TREE_HP: int = 5
const TREE_XP: int = 3
const TREE_RESPAWN: float = 240.0

# --------------------------------------------------
# BUILDING
# --------------------------------------------------
const GRID: float = 3.0
const STORY: float = 3.12

const BUILD_ORDER: Array = ["floor", "wall", "door", "window", "roof", "stairs", "bridge", "fence", "stone_wall", "campfire"]
const PIECES: Dictionary = {
	"floor": {"name": "Wooden Floor", "cost": {"wood": 4}, "slot": "F"},
	"wall": {"name": "Wooden Wall", "cost": {"wood": 4}, "slot": "W"},
	"door": {"name": "Doorway", "cost": {"wood": 4}, "slot": "W"},
	"window": {"name": "Window Wall", "cost": {"wood": 5, "iron": 1}, "slot": "W"},
	"roof": {"name": "Roof", "cost": {"wood": 3, "hide_deer": 1}, "slot": "R"},
	"stairs": {"name": "Stairs", "cost": {"wood": 6}, "slot": "S"},
	"bridge": {"name": "Bridge", "cost": {"wood": 5, "iron": 1}, "slot": "F"},
	"fence": {"name": "Fence", "cost": {"wood": 2}, "slot": "W"},
	"stone_wall": {"name": "Stone Wall", "cost": {"stone": 6, "iron": 1}, "slot": "W"},
	"campfire": {"name": "Campfire (heals)", "cost": {"wood": 3, "stone": 4}, "slot": "C"},
}

# --------------------------------------------------
# SHOP
# --------------------------------------------------
const SHOP: Array = [
	{"id": "ammo", "name": "Ammo ×20"},
	{"id": "medkit", "name": "Medkit (+60 HP)"},
	{"id": "rifle", "name": "Rifle upgrade"},
	{"id": "pickaxe", "name": "Pickaxe upgrade"},
	{"id": "axe", "name": "Axe upgrade"},
]


static func item_name(item_id: String) -> String:
	if ITEMS.has(item_id):
		return ITEMS[item_id]["name"]
	return item_id


static func sell_value(inv: Dictionary, level: int = 1, include_materials: bool = false) -> int:
	var total: int = 0
	for item_id in inv.keys():
		if ITEMS.has(item_id) and (include_materials or not MATERIALS.has(item_id)):
			total += int(inv[item_id]) * sell_price(item_id, level)
	return total


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost.keys():
		parts.append("%d %s" % [int(cost[k]), item_name(k)])
	return ", ".join(parts)


static func can_afford(inv: Dictionary, cost: Dictionary) -> bool:
	for k in cost.keys():
		if int(inv.get(k, 0)) < int(cost[k]):
			return false
	return true


## Price of the next purchase; -1 when already maxed.
static func shop_price(item_id: String, stats: Dictionary) -> int:
	match item_id:
		"ammo":
			return 10 if int(stats.get("ammo", 0)) < int(bonuses(int(stats.get("level", 1)))["max_ammo"]) else -1
		"medkit":
			return 20 if int(stats.get("medkits", 0)) < int(bonuses(int(stats.get("level", 1)))["max_medkits"]) else -1
		"rifle", "pickaxe", "axe":
			var lvl: int = int(stats.get(item_id, 1))
			var base: int = 120 if item_id == "rifle" else 100
			return base * lvl if lvl < MAX_TOOL_LEVEL else -1
	return -1


static func tool_name(tool: String, lvl: int) -> String:
	var names: Array = TOOL_NAMES.get(tool, [])
	return String(names[clampi(lvl, 1, 3)]) if names.size() > 3 else tool


static func mine_cooldown(pick_level: int, char_idx: int, level: int = 1) -> float:
	return (0.8 - 0.15 * float(pick_level - 1)) * float(CHARACTERS[char_idx]["mine"]) * float(bonuses(level)["gather"])


static func chop_cooldown(axe_level: int, char_idx: int, level: int = 1) -> float:
	return (0.85 - 0.15 * float(axe_level - 1)) * float(CHARACTERS[char_idx]["chop"]) * float(bonuses(level)["gather"])


# --------------------------------------------------
# LEVELS
# --------------------------------------------------
static func xp_to_next(level: int) -> int:
	return 30 + 15 * level + level * level


static func max_hp(level: int) -> float:
	return 100.0 + 3.0 * float(level - 1)


static func level_damage_mult(level: int) -> float:
	return 1.0 + 0.01 * float(level - 1)


static func time_text(t: float) -> String:
	var hours: float = fmod(t * 24.0 + 6.0, 24.0)
	var h: int = int(hours)
	var m: int = int((hours - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]


# --------------------------------------------------
# LEVEL BONUSES
# --------------------------------------------------
## Building pieces that unlock at a character level.
const UNLOCKS: Dictionary = {"window": 2, "bridge": 3, "stairs": 4, "campfire": 5, "stone_wall": 6}


static func bonuses(level: int) -> Dictionary:
	var l: float = float(level - 1)
	return {
		"max_hp": max_hp(level),
		"damage": 1.0 + 0.01 * l,
		"speed": 1.0 + 0.0025 * l,
		"gather": 1.0 - 0.003 * l,
		"sell": 1.0 + 0.005 * l,
		"double": 0.005 * l,
		"regen": float(level / 10),
		"max_ammo": MAX_AMMO + 2 * (level - 1),
		"max_medkits": MAX_MEDKITS + level / 20,
	}


static func bonus_lines(level: int) -> Array:
	var b: Dictionary = bonuses(level)
	var lines: Array = [
		"Max health: %d" % int(b["max_hp"]),
		"Rifle damage: +%d%%" % roundi((float(b["damage"]) - 1.0) * 100.0),
		"Move speed: +%.1f%%" % ((float(b["speed"]) - 1.0) * 100.0),
		"Mining & chopping speed: +%.1f%%" % ((1.0 - float(b["gather"])) * 100.0),
		"Trader pays: +%.1f%%" % ((float(b["sell"]) - 1.0) * 100.0),
		"Double loot chance: %.1f%%" % (float(b["double"]) * 100.0),
		"Max ammo: %d   •   Max medkits: %d" % [int(b["max_ammo"]), int(b["max_medkits"])],
	]
	if float(b["regen"]) > 0.0:
		lines.append("Health regen: %d HP every 5 s" % int(b["regen"]))
	else:
		lines.append("Health regen: unlocks at Lv. 10")
	return lines


static func level_rewards(new_level: int) -> Dictionary:
	return {"coins": new_level * 15, "ammo": 10, "medkits": 1 if new_level % 5 == 0 else 0}


static func next_milestone(level: int) -> String:
	for kind in BUILD_ORDER:
		var need: int = int(UNLOCKS.get(kind, 1))
		if need > level:
			return "Lv. %d unlocks %s" % [need, PIECES[kind]["name"]]
	if level < 10:
		return "Lv. 10 unlocks health regeneration"
	if level % 5 != 0:
		return "Lv. %d gives a free medkit" % (level + 5 - level % 5)
	return "Every level: more health, damage, speed and coins"


static func unlock_level(kind: String) -> int:
	return int(UNLOCKS.get(kind, 1))


static func sell_price(item_id: String, level: int) -> int:
	if not ITEMS.has(item_id):
		return 0
	return maxi(1, roundi(float(ITEMS[item_id]["price"]) * float(bonuses(level)["sell"])))
