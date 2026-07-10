# KeyPickup.gd
# Représente une clé physique posée dans le niveau.
# Ajouter ce nœud au groupe "Pickup" dans l'Inspecteur (onglet Node > Groups).
class_name KeyPickup
extends Node3D

## La ressource ItemData liée à cette clé (à assigner dans l'Inspecteur)
@export var item_data: ItemData = null

func _ready() -> void:
	# Sécurité : vérifie que la donnée est bien assignée
	if item_data == null:
		push_warning("KeyPickup '%s' : aucun ItemData assigné !" % name)
	# S'assure que le nœud est bien dans le groupe "Pickup"
	if not is_in_group("Pickup"):
		add_to_group("Pickup")

## Appelée par l'InteractionManager quand le joueur ramasse cet objet
## Appelée par l'InteractionManager quand le joueur ramasse cet objet
func get_picked_up() -> ItemData:
	var data = item_data
	if data == null or not data.stays_on_ground:
		queue_free() # Supprime l'objet du monde, sauf si stays_on_ground est activé
	return data
