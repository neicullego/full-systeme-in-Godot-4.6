extends Area3D

## Zone de sortie de bassin.
## Enfants requis :
##   - ExitMarker (Marker3D) → positionné sur le rebord, au sol, légèrement en retrait de l'eau.

@onready var exit_marker: Marker3D = $ExitMarker

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func get_exit_position() -> Vector3:
	if exit_marker:
		return exit_marker.global_position
	# Fallback si le marker n'existe pas
	return global_position + Vector3(0, 1.5, 0)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	var im: Node = body.get_node_or_null("InteractionManager")
	if im:
		im.register_climb_zone(self)
		print("[ClimbOut] Joueur entré dans la zone de sortie.")

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	var im: Node = body.get_node_or_null("InteractionManager")
	if im:
		im.unregister_climb_zone(self)
		print("[ClimbOut] Joueur sorti de la zone de sortie.")
