## Root of the prototype scene. Wires global hotkeys to the camera.
extends Node3D

@onready var camera: RtsCamera = $RtsCamera
@onready var region: Node3D = $Region


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_focus_hub"):
		camera.focus_on(region.get_platform_position("Hub"))
		get_viewport().set_input_as_handled()
