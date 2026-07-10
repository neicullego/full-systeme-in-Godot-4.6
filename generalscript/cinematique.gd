extends Node3D
## Script à attacher à la racine de la scène de cinématique.
## La racine peut être n'importe quel type de noeud : ce script ne gère
## que la temporisation et le signal de fin.

signal finished

## Nom de l'animation à jouer si la scène contient un AnimationPlayer nommé "AnimationPlayer".
@export var animation_name: StringName = &"intro"

## Durée de repli (en secondes) si aucun AnimationPlayer/animation n'est trouvé.
## Pratique pour tester le flux avant même d'avoir le contenu de la cinématique.
@export var fallback_duration: float = 0.0

## Autorise à passer la cinématique avec "ui_accept" (Entrée/Espace).
## Désactivé automatiquement en multijoueur (voir _ready) pour ne jamais
## désynchroniser l'arrivée des joueurs dans le monde.
@export var allow_skip: bool = true

@onready var _anim_player: AnimationPlayer = $AnimationPlayer

var _done := false


func _ready() -> void:
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		allow_skip = false   # sécurité : un skip individuel désynchroniserait les joueurs

	if _anim_player and _anim_player.has_animation(animation_name):
		_anim_player.animation_finished.connect(func(_n): _finish())
		_anim_player.play(animation_name)
	else:
		get_tree().create_timer(fallback_duration).timeout.connect(_finish)


func _unhandled_input(event: InputEvent) -> void:
	if allow_skip and event.is_action_pressed("ui_accept"):
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
