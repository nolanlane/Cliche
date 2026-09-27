class_name FuelCan
extends Area3D
## Authorable Fuel Can Pickup for lighter fluid.
## Visible and selectable in Godot 3D editor.

signal fuel_collected(amount: float)

@export var fuel_amount: float = 40.0
@export var grounded: bool = false

@onready var visual: Node3D = get_node_or_null("Visual")
@onready var glow: OmniLight3D = get_node_or_null("Glow")

var is_collected: bool = false
var base_y: float = 0.0
var seed_offset: float = 0.0
var elapsed: float = 0.0

func _enter_tree() -> void:
	add_to_group("fuel_can")

func _ready() -> void:
	add_to_group("fuel_can")
	base_y = position.y
	seed_offset = randf() * 10.0
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if is_collected:
		return
	elapsed += delta
	if visual != null and not grounded:
		visual.rotation.y += delta * 1.35
		visual.position.y = sin(elapsed * 2.2 + seed_offset) * 0.035

func _on_body_entered(body: Node3D) -> void:
	if is_collected:
		return
	if body.is_in_group("player") or body.name == "Player":
		collect(body)

func collect(player_node: Node3D) -> void:
	if is_collected:
		return
	is_collected = true

	if player_node != null and player_node.has_method("add_fuel"):
		player_node.add_fuel(fuel_amount)
	elif player_node != null and "lighter_fuel" in player_node:
		player_node.lighter_fuel = clampf(player_node.lighter_fuel + fuel_amount, 0.0, 100.0)

	fuel_collected.emit(fuel_amount)

	# Notify HUD if in tree
	var main_node := get_tree().current_scene
	if main_node != null and main_node.has_method("_show_hud_toast"):
		main_node._show_hud_toast("+40% LIGHTER FLUID")
	elif main_node != null and main_node.has_node("HUD"):
		var hud := main_node.get_node("HUD")
		if hud.has_method("show_toast"):
			hud.show_toast("+40% LIGHTER FLUID")

	# Tactile collection bounce & vanish animation
	if visual != null:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		if glow != null:
			tween.tween_property(glow, "light_energy", 2.2, 0.08)
			tween.tween_property(glow, "light_energy", 0.0, 0.20).set_delay(0.08)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()
