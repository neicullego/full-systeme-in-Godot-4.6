# OxygenTank.gd
# Bouteille d'oxygène posée dans le niveau : ne va JAMAIS dans l'inventaire,
# reste toujours à sa position. Interagir avec elle redonne de l'air au joueur.
# Ajouter ce nœud au groupe "OxygenTank" dans l'Inspecteur (onglet Node > Groups).
class_name OxygenTank
extends Node3D

## Secondes d'air redonnées à chaque utilisation — réglable par bouteille dans l'Inspecteur
@export var oxygen_refill_amount: float = 15.0

## Délai minimum (s) avant de pouvoir réutiliser CETTE bouteille.
## Mettez 0 pour un usage illimité, sans aucune recharge.
@export var reuse_cooldown: float = 3.0

var _cooldown_remaining: float = 0.0

func _ready() -> void:
	if not is_in_group("OxygenTank"):
		add_to_group("OxygenTank")

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = max(_cooldown_remaining - delta, 0.0)

## Appelée par l'InteractionManager quand le joueur interagit avec cette bouteille.
## Renvoie true si l'air a bien été redonné, false si elle est encore en recharge
## (déclenche alors la petite vibration de refus, comme pour un mauvais outil).
func try_use(player: CharacterBody3D) -> bool:
	if _cooldown_remaining > 0.0:
		return false
	if player == null or not player.has_method("refill_oxygen"):
		return false

	player.refill_oxygen(oxygen_refill_amount)
	_cooldown_remaining = reuse_cooldown
	print("[OxygenTank] ", oxygen_refill_amount, "s d'air redonnés.")
	return true
