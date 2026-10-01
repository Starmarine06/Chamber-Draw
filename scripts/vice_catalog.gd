extends RefCounted

## Everything you can smoke or drink at the table. All brands are fictional.
## Pickers (scripts/ui/vice_picker.gd) and the first-person sessions read from here.

# ── Smokes ────────────────────────────────────────────────────────────

const CIGARETTES := [
	{"name": "Ember Gold", "paper": Color(0.95, 0.94, 0.9), "filter": Color(0.78, 0.55, 0.3), "pack": Color(0.55, 0.08, 0.12), "band": Color(0.79, 0.64, 0.36), "burn": 0.028, "len": 1.0, "tag": "Classic. Smooth."},
	{"name": "Night 100s", "paper": Color(0.1, 0.1, 0.12), "filter": Color(0.9, 0.9, 0.86), "pack": Color(0.08, 0.08, 0.1), "band": Color(0.75, 0.75, 0.8), "burn": 0.022, "len": 1.35, "tag": "Long, black paper."},
	{"name": "Red Vesper", "paper": Color(0.95, 0.94, 0.9), "filter": Color(0.6, 0.08, 0.1), "pack": Color(0.75, 0.1, 0.1), "band": Color(0.9, 0.85, 0.7), "burn": 0.033, "len": 0.95, "tag": "Harsh. Burns fast."},
	{"name": "Frost Menthol", "paper": Color(0.92, 0.96, 0.97), "filter": Color(0.35, 0.72, 0.68), "pack": Color(0.12, 0.45, 0.5), "band": Color(0.85, 0.95, 0.95), "burn": 0.03, "len": 1.0, "tag": "Cold and clean."},
]

const CIGARS := [
	{"name": "Dorado Corona", "wrapper": Color(0.42, 0.26, 0.12), "band": Color(0.85, 0.7, 0.25), "box": Color(0.35, 0.2, 0.1), "burn": 0.013, "len": 1.0, "girth": 1.0, "tag": "Balanced. Golden band."},
	{"name": "Maduro Noir", "wrapper": Color(0.15, 0.08, 0.05), "band": Color(0.7, 0.1, 0.12), "box": Color(0.12, 0.07, 0.05), "burn": 0.011, "len": 0.9, "girth": 1.3, "tag": "Dark, fat robusto."},
	{"name": "Gran Churchill", "wrapper": Color(0.5, 0.33, 0.16), "band": Color(0.2, 0.5, 0.3), "box": Color(0.3, 0.2, 0.1), "burn": 0.009, "len": 1.45, "girth": 1.1, "tag": "A very long evening."},
	{"name": "Petit Claro", "wrapper": Color(0.62, 0.48, 0.26), "band": Color(0.85, 0.85, 0.8), "box": Color(0.5, 0.36, 0.2), "burn": 0.02, "len": 0.7, "girth": 0.8, "tag": "Quick, mild."},
]

# ── Drinks ────────────────────────────────────────────────────────────
# glass: tumbler | shot | martini | mug | wine | flute | snifter
# abv: strength weight for getting drunk (1.0 ≈ whiskey)
# sip: how much of the glass one scroll tick drains

const DRINKS := {
	"whiskey": {"label": "Whiskey", "glass": "tumbler", "color": Color(0.85, 0.45, 0.08), "bottle": Color(0.35, 0.2, 0.08), "abv": 1.0, "sip": 0.05,
		"brands": [{"name": "Old Hollow"}, {"name": "Copper Ridge"}, {"name": "Black Anvil"}]},
	"bourbon": {"label": "Bourbon", "glass": "tumbler", "color": Color(0.72, 0.32, 0.06), "bottle": Color(0.3, 0.14, 0.06), "abv": 1.0, "sip": 0.05,
		"brands": [{"name": "Ironwood Reserve"}, {"name": "Red Barrel"}, {"name": "Oakheart"}]},
	"scotch": {"label": "Scotch", "glass": "tumbler", "color": Color(0.8, 0.52, 0.16), "bottle": Color(0.16, 0.24, 0.14), "abv": 1.05, "sip": 0.045,
		"brands": [{"name": "Glen Morrow"}, {"name": "Highmoor 12"}, {"name": "Ardcairn Smoke", "color": Color(0.6, 0.38, 0.1)}]},
	"vodka": {"label": "Vodka", "glass": "shot", "color": Color(0.85, 0.92, 0.97), "bottle": Color(0.7, 0.85, 0.95), "abv": 1.1, "sip": 0.14,
		"brands": [{"name": "Frostbyte"}, {"name": "Silver Wolf"}, {"name": "Polar Nine"}]},
	"gin": {"label": "Gin", "glass": "martini", "color": Color(0.82, 0.93, 0.9), "bottle": Color(0.2, 0.45, 0.6), "abv": 1.0, "sip": 0.09,
		"brands": [{"name": "Juniper & Crow"}, {"name": "Blue Lantern"}, {"name": "Sable Botanic"}]},
	"rum": {"label": "Rum", "glass": "tumbler", "color": Color(0.45, 0.2, 0.06), "bottle": Color(0.25, 0.1, 0.05), "abv": 0.95, "sip": 0.05,
		"brands": [{"name": "Dead Reckoning"}, {"name": "Captain Ash"}, {"name": "Sugarcane Jack", "color": Color(0.9, 0.7, 0.3)}]},
	"tequila": {"label": "Tequila", "glass": "shot", "color": Color(0.92, 0.78, 0.32), "bottle": Color(0.5, 0.45, 0.15), "abv": 1.0, "sip": 0.14,
		"brands": [{"name": "Agave Sol"}, {"name": "Diablo Azul"}, {"name": "Casa Marlo", "color": Color(0.9, 0.9, 0.85)}]},
	"cognac": {"label": "Cognac", "glass": "snifter", "color": Color(0.7, 0.35, 0.08), "bottle": Color(0.25, 0.12, 0.06), "abv": 1.0, "sip": 0.07,
		"brands": [{"name": "Maison Vesper"}, {"name": "Delacroix XO"}, {"name": "Fontaine Rare"}]},
	"beer": {"label": "Beer", "glass": "mug", "color": Color(0.92, 0.66, 0.12), "bottle": Color(0.35, 0.22, 0.05), "abv": 0.35, "sip": 0.035,
		"brands": [{"name": "Rusty Lager"}, {"name": "Dark Harbor Stout", "color": Color(0.14, 0.07, 0.03)}, {"name": "Pale Moon IPA", "color": Color(0.95, 0.75, 0.2)}]},
	"wine": {"label": "Wine", "glass": "wine", "color": Color(0.45, 0.05, 0.12), "bottle": Color(0.1, 0.18, 0.1), "abv": 0.6, "sip": 0.06,
		"brands": [{"name": "Chateau Noir"}, {"name": "Rosa Vale", "color": Color(0.85, 0.4, 0.5)}, {"name": "Bianco Lume", "color": Color(0.9, 0.85, 0.5)}]},
	"champagne": {"label": "Champagne", "glass": "flute", "color": Color(0.95, 0.88, 0.5), "bottle": Color(0.12, 0.2, 0.1), "abv": 0.6, "sip": 0.07,
		"brands": [{"name": "Perle d'Or"}, {"name": "Brut Etoile"}, {"name": "Velvet Rose", "color": Color(0.95, 0.65, 0.65)}]},
	"absinthe": {"label": "Absinthe", "glass": "shot", "color": Color(0.5, 0.85, 0.3), "bottle": Color(0.15, 0.5, 0.15), "abv": 1.6, "sip": 0.12,
		"brands": [{"name": "La Fee Verte"}, {"name": "Green Muse"}, {"name": "Wormwood 68"}]},
}

const DRINK_ORDER := ["whiskey", "bourbon", "scotch", "vodka", "gin", "rum", "tequila", "cognac", "beer", "wine", "champagne", "absinthe"]

# Remembered picks for the session: {cat: int/String, brand: int}
static var last_smoke := {"cat": "cigarette", "brand": 0}
static var last_drink := {"cat": "whiskey", "brand": 0}


## Resolved product for the smoke session.
static func smoke_product(cat: String, brand: int) -> Dictionary:
	var list: Array = CIGARS if cat == "cigar" else CIGARETTES
	var def: Dictionary = list[clampi(brand, 0, list.size() - 1)]
	var out := def.duplicate()
	out["kind"] = cat
	out["id"] = "%s:%s" % [cat, def.name]
	return out


## Resolved drink for the drink session.
static func drink_product(cat: String, brand: int) -> Dictionary:
	if not DRINKS.has(cat):
		cat = "whiskey"
	var def: Dictionary = DRINKS[cat]
	var brands: Array = def.brands
	var b: Dictionary = brands[clampi(brand, 0, brands.size() - 1)]
	var out := def.duplicate()
	out["cat"] = cat
	out["brand"] = b.name
	out["color"] = b.get("color", def.color)
	out["id"] = "%s:%s" % [cat, b.name]
	return out
