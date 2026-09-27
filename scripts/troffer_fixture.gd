@tool
class_name TrofferFixture
extends Node3D
## Authorable Fluorescent Troffer Fixture for Backrooms Level.
## Visible and selectable in Godot 3D editor.

enum FixtureType { NORMAL, STUTTER, DYING, DEAD, SLOW_PULSE, FAINT_EMERGENCY }

@export var type: FixtureType = FixtureType.NORMAL:
	set(val):
		type = val
		if is_inside_tree():
			_update_visuals()

@export var seed_offset: float = 0.0
@export var is_crawlspace: bool = false:
	set(val):
		is_crawlspace = val
		if is_inside_tree():
			_update_visuals()

@onready var frame: MeshInstance3D = get_node_or_null("Frame")
@onready var panel: MeshInstance3D = get_node_or_null("Panel")
@onready var spot_light: SpotLight3D = get_node_or_null("SpotLight")
@onready var fill_light: OmniLight3D = get_node_or_null("FillLight")

var base_spot_energy: float = 1.42
var base_fill_energy: float = 0.68
var base_emission: float = 1.45
var spot_color: Color = Color("#ebf0cb")
var stutter_timer: float = 0.0
var stutter_state: int = 0
var panel_material: StandardMaterial3D

func _enter_tree() -> void:
	add_to_group("troffer_fixture")

func _ready() -> void:
	add_to_group("troffer_fixture")
	_update_visuals()

func _update_visuals() -> void:
	# Ensure nodes exist
	if frame == null:
		frame = get_node_or_null("Frame")
	if panel == null:
		panel = get_node_or_null("Panel")
	if spot_light == null:
		spot_light = get_node_or_null("SpotLight")
	if fill_light == null:
		fill_light = get_node_or_null("FillLight")

	# Configure base parameters according to type
	match type:
		FixtureType.DEAD:
			base_spot_energy = 0.0
			base_fill_energy = 0.0
			base_emission = 0.0
			spot_color = Color("#222320")
		FixtureType.DYING:
			spot_color = Color("#d4cca2")
			base_spot_energy = 0.88
			base_fill_energy = 0.44
			base_emission = 0.78
		FixtureType.FAINT_EMERGENCY:
			spot_color = Color("#cad4b2")
			base_spot_energy = 0.66
			base_fill_energy = 0.34
			base_emission = 0.52
		_:
			if is_crawlspace or global_position.y < 1.5:
				base_spot_energy = 0.74
				base_fill_energy = 0.28
				spot_color = Color("#b4bcaf")
				base_emission = 1.45
			else:
				base_spot_energy = 1.42
				base_fill_energy = 0.68
				base_emission = 1.45
				spot_color = Color("#ebf0cb")

	# Update panel material instance
	if panel != null and panel.mesh != null:
		var mat := panel.get_surface_override_material(0) as StandardMaterial3D
		if mat == null:
			var base_mat := panel.mesh.material as StandardMaterial3D
			if base_mat != null:
				mat = base_mat.duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			panel.set_surface_override_material(0, mat)
		panel_material = mat
		if type == FixtureType.DEAD:
			mat.albedo_color = Color("#222320")
			mat.emission_enabled = false
		else:
			mat.albedo_color = spot_color
			mat.emission_enabled = true
			mat.emission = spot_color
			mat.emission_energy_multiplier = base_emission

	if spot_light != null:
		if type == FixtureType.DEAD:
			spot_light.visible = false
		else:
			spot_light.visible = true
			spot_light.light_color = spot_color
			spot_light.light_energy = base_spot_energy

	if fill_light != null:
		if type == FixtureType.DEAD:
			fill_light.visible = false
		else:
			fill_light.visible = true
			fill_light.light_color = spot_color
			fill_light.light_energy = base_fill_energy

func apply_energy(energy_mul: float) -> void:
	if type == FixtureType.DEAD:
		return
	if spot_light != null:
		spot_light.light_energy = base_spot_energy * energy_mul
	if fill_light != null:
		fill_light.light_energy = base_fill_energy * energy_mul
	if panel_material != null:
		panel_material.emission_energy_multiplier = base_emission * energy_mul
