@tool
class_name ObserverAnchor
extends Marker3D
## Authored spatial anchor for Observer encounter placement.
## Level designers can drag these markers in the 3D viewport and assign semantic roles.

@export var role: StringName = &"doorway"

func _enter_tree() -> void:
	add_to_group("observer_anchor")

func _ready() -> void:
	add_to_group("observer_anchor")
