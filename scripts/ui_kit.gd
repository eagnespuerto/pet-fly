class_name UIKit
extends RefCounted

## Helpers that build PetFly's HUD out of the Kenney UI pack (CC0).
##
## Kenney's button sprites are rounded rectangles, so they are wrapped as
## nine-patch style boxes and stretch cleanly to any size. Meters use
## TextureProgressBar, which crops the fill texture instead of squashing it, so
## the rounded end caps keep their shape at every value.

const GREY := "Grey"
const BLUE := "Blue"
const GREEN := "Green"
const RED := "Red"
const YELLOW := "Yellow"

const INK := Color(0.95, 0.97, 0.99)
const INK_DIM := Color(0.70, 0.75, 0.82)
const INK_FAINT := Color(0.52, 0.57, 0.64)

const FONT_REGULAR := "res://assets/fonts/Kenney Future Narrow.ttf"
const FONT_BOLD := "res://assets/fonts/Kenney Future.ttf"

## Corner size of the Kenney button sprites, in source pixels.
const PATCH := 20


static func font(bold := false) -> FontFile:
	return load(FONT_BOLD if bold else FONT_REGULAR)


static func tex(colour: String, name: String) -> Texture2D:
	return load("res://assets/ui/%s/%s" % [colour, name])


static func label(text: String, size: int, colour := INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func stylebox(colour: String, sprite := "button_rectangle_depth_flat.png",
		tint := Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(colour, sprite)
	sb.set_texture_margin(SIDE_LEFT, PATCH)
	sb.set_texture_margin(SIDE_RIGHT, PATCH)
	sb.set_texture_margin(SIDE_TOP, PATCH)
	sb.set_texture_margin(SIDE_BOTTOM, PATCH)
	sb.modulate_color = tint
	return sb


static func button(text: String, colour := BLUE, size := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.95, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.78, 0.82, 0.6))
	b.add_theme_stylebox_override("normal", stylebox(colour))
	b.add_theme_stylebox_override("hover", stylebox(colour, "button_rectangle_depth_flat.png",
			Color(1.18, 1.18, 1.18)))
	b.add_theme_stylebox_override("pressed", stylebox(colour, "button_rectangle_flat.png"))
	b.add_theme_stylebox_override("disabled", stylebox(GREY, "button_rectangle_depth_flat.png",
			Color(0.75, 0.75, 0.78)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func panel(tint := Color(0.14, 0.17, 0.23, 0.93)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
			stylebox(GREY, "button_square_depth_flat.png", tint))
	return p


static func meter(colour := GREEN, height := 16) -> TextureProgressBar:
	var m := TextureProgressBar.new()
	m.texture_under = tex(GREY, "slide_horizontal_grey.png")
	m.texture_progress = tex(colour, "slide_horizontal_color.png")
	m.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	m.nine_patch_stretch = true
	m.stretch_margin_left = 8
	m.stretch_margin_right = 8
	m.stretch_margin_top = 0
	m.stretch_margin_bottom = 0
	m.min_value = 0.0
	m.max_value = 1.0
	m.step = 0.001
	m.custom_minimum_size = Vector2(0, height)
	# Darkening the track turns Kenney's slider groove into a recessed bar
	# rather than something that reads as a draggable handle.
	m.tint_under = Color(0.34, 0.37, 0.44)
	return m


static func set_meter_colour(m: TextureProgressBar, colour: String) -> void:
	var t := tex(colour, "slide_horizontal_color.png")
	if m.texture_progress != t:
		m.texture_progress = t


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
