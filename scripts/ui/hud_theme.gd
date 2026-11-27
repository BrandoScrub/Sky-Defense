## The look of every HUD panel, button, tab and tooltip: dark iron plate in a
## brass frame with a rivet in each corner, warm parchment text, and two fonts
## (Cinzel, engraved capitals, for titles and names; Barlow Semi Condensed, a
## compact industrial face, for numbers and body text).
##
## HudTheme.apply() is called once when the game starts. It merges these looks
## into Godot's default theme, so every Control in the game (and every
## tooltip) picks them up without each script setting its own colours.
## Use a variation on a node to opt in to a special look:
##   label.theme_type_variation = "Title"     Cinzel, amber (card titles)
##   label.theme_type_variation = "Heading"   Cinzel, parchment (banners, tabs)
##   panel.theme_type_variation = "Plate"     brass frame with rivets
##   panel.theme_type_variation = "Strip"     thin bar with a brass rule underneath
class_name HudTheme
extends RefCounted

## Palette. Kept here so every script uses the same few colours.
const IRON := Color(0.085, 0.075, 0.065, 0.93)
const IRON_LIGHT := Color(0.16, 0.135, 0.11, 0.95)
const BRASS := Color(0.78, 0.6, 0.32)
const BRASS_DIM := Color(0.48, 0.37, 0.2)
const RIVET := Color(0.9, 0.74, 0.44)
const PARCHMENT := Color(0.95, 0.9, 0.78)
const AMBER := Color(1.0, 0.78, 0.38)
const WARN := Color(1.0, 0.5, 0.38)
const GOOD := Color(0.6, 0.92, 0.7)
const COLD := Color(0.65, 0.82, 1.0)

const FONT_BODY := "res://assets/fonts/BarlowSemiCondensed-Medium.ttf"
const FONT_BOLD := "res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"
const FONT_TITLE := "res://assets/fonts/Cinzel.ttf"

static var _applied := false
static var _title_font: Font
static var _body_font: Font


## Merges the HUD look into the default theme. Safe to call more than once.
static func apply() -> void:
	if _applied:
		return
	_applied = true
	var base := ThemeDB.get_default_theme()
	base.merge_with(build())
	base.default_font = body_font()
	base.default_font_size = 16


static func body_font() -> Font:
	if _body_font == null:
		_body_font = load(FONT_BODY)
	return _body_font


## Cinzel at a bold weight (the file holds every weight).
static func title_font() -> Font:
	if _title_font == null:
		var v := FontVariation.new()
		v.base_font = load(FONT_TITLE)
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		_title_font = v
	return _title_font


static func build() -> Theme:
	var t := Theme.new()
	var body := body_font()
	var bold: Font = load(FONT_BOLD)
	var title := title_font()

	# Text.
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", title)
	t.set_color("font_color", "Title", AMBER)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", title)
	t.set_color("font_color", "Heading", PARCHMENT)

	# Panels.
	var plate := riveted(IRON)
	t.set_stylebox("panel", "PanelContainer", plate)
	t.set_stylebox("panel", "Panel", plate)
	t.set_type_variation("Plate", "PanelContainer")
	t.set_stylebox("panel", "Plate", plate)
	t.set_type_variation("Strip", "PanelContainer")
	t.set_stylebox("panel", "Strip", strip())

	# Buttons: iron with a dim brass edge; hover lights the edge; pressed or
	# toggled on fills with warm brass.
	var normal := flat(IRON_LIGHT, BRASS_DIM, 1)
	var hover := flat(Color(0.22, 0.18, 0.13, 0.97), BRASS, 1)
	var pressed := flat(Color(0.42, 0.31, 0.15, 0.97), RIVET, 2)
	var disabled := flat(Color(0.1, 0.09, 0.08, 0.7), Color(0.3, 0.25, 0.18), 1)
	for kind in ["Button"]:
		t.set_stylebox("normal", kind, normal)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("hover_pressed", kind, pressed)
		t.set_stylebox("disabled", kind, disabled)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_font("font", kind, bold)
		t.set_color("font_color", kind, PARCHMENT)
		t.set_color("font_hover_color", kind, Color(1, 0.95, 0.85))
		t.set_color("font_pressed_color", kind, Color(1, 0.93, 0.75))
		t.set_color("font_hover_pressed_color", kind, Color(1, 0.93, 0.75))
		t.set_color("font_disabled_color", kind, Color(0.6, 0.55, 0.48))
	t.set_color("font_color", "CheckBox", PARCHMENT)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	# Tabs above the command grid read as engraved name plates.
	t.set_type_variation("TabPlate", "Button")
	t.set_font("font", "TabPlate", title)
	t.set_font_size("font_size", "TabPlate", 15)

	# Tooltips: the same riveted plate, a little more opaque.
	t.set_stylebox("panel", "TooltipPanel", riveted(Color(0.07, 0.06, 0.05, 0.97), 10))
	t.set_color("font_color", "TooltipLabel", PARCHMENT)
	t.set_font("font", "TooltipLabel", body)
	t.set_font_size("font_size", "TooltipLabel", 15)
	return t


static func flat(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(2)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


## A thin bar for the top of the screen: iron with a double brass rule along
## the bottom edge.
static func strip() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = IRON
	s.border_color = BRASS
	s.border_width_bottom = 3
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## A plate drawn as a small nine-slice image: a brass frame with a darker
## inner line and a rivet in each corner. The corners never stretch, so the
## rivets stay round at any panel size.
static func riveted(fill: Color, margin := 12) -> StyleBoxTexture:
	const N := 32
	const C := 10  # corner size that never stretches
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for i in N:
		for j in N:
			var edge := mini(mini(i, j), mini(N - 1 - i, N - 1 - j))
			if edge == 0:
				img.set_pixel(i, j, BRASS_DIM)
			elif edge == 1:
				img.set_pixel(i, j, BRASS)
			elif edge == 2:
				img.set_pixel(i, j, BRASS_DIM.darkened(0.3))
	# Rivets: a lit dome with a dark rim.
	for corner in [Vector2(5.5, 5.5), Vector2(N - 6.5, 5.5), Vector2(5.5, N - 6.5), Vector2(N - 6.5, N - 6.5)]:
		for i in range(int(corner.x) - 3, int(corner.x) + 4):
			for j in range(int(corner.y) - 3, int(corner.y) + 4):
				var d := Vector2(i, j).distance_to(corner)
				if d <= 1.0:
					img.set_pixel(i, j, Color(1.0, 0.92, 0.7))
				elif d <= 2.0:
					img.set_pixel(i, j, RIVET)
				elif d <= 2.7:
					img.set_pixel(i, j, BRASS_DIM.darkened(0.4))
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = C
	s.texture_margin_right = C
	s.texture_margin_top = C
	s.texture_margin_bottom = C
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin - 4
	s.content_margin_bottom = margin - 4
	return s
