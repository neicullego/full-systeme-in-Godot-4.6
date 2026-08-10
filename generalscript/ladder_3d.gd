extends Node3D
class_name Ladder3D
## Échelle grimpable façon Minecraft — à attacher au nœud racine de la scène d'échelle.
##
## STRUCTURE DE SCÈNE ATTENDUE :
##
##   Ladder (Node3D)  ← ce script
##   ├── MeshInstance3D              (le visuel de l'échelle)
##   ├── StaticBody3D                (optionnel : collision physique des montants,
##   │   └── CollisionShape3D          si le joueur doit pouvoir buter dessus)
##   └── Area3D                      (⚠️ doit s'appeler exactement "Area3D")
##       └── CollisionShape3D        (une boîte fine collée à la face de l'échelle ;
##                                     fais-la dépasser un peu en haut, jusqu'au niveau
##                                     du sol du palier d'arrivée, pour une sortie fluide)
##
## ORIENTATION : oriente ce nœud comme une porte. La face "avant" — celle vers
## laquelle le joueur doit marcher pour s'accrocher — correspond à l'axe -Z local
## (la flèche bleue du gizmo doit pointer vers la zone où se tient le joueur).
## Si la grimpe se déclenche à l'envers (monter en reculant, ou aucune accroche
## en marchant dessus), coche `invert_direction` ci-dessous au lieu de retoucher
## la rotation du nœud.

@export var invert_direction: bool = false

@onready var area: Area3D = $Area3D


func _ready() -> void:
	if not area:
		push_warning("Ladder3D (%s) : aucun nœud 'Area3D' trouvé en enfant direct !" % name)
		return
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and body.has_method("_enter_ladder_zone"):
		body._enter_ladder_zone(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("Player") and body.has_method("_exit_ladder_zone"):
		body._exit_ladder_zone(self)


## Direction (horizontale, normalisée) dans laquelle le joueur doit marcher pour
## "entrer" dans l'échelle et s'y accrocher. Utilisée par first_player.gd pour
## savoir si l'input du joueur pousse vers l'échelle (monte) ou à l'opposé (descend).
func get_into_direction() -> Vector3:
	var dir: Vector3 = global_transform.basis.z
	if invert_direction:
		dir = -dir
	dir.y = 0.0
	return dir.normalized()
