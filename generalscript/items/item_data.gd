class_name ItemData
extends Resource

@export var item_id: String = ""
@export var item_name: String = ""
@export var item_description: String = ""
@export var item_image: Texture2D = null
@export var pickup_scene_path: String = ""  # ← cette ligne doit être présente

@export var stays_on_ground: bool = false

enum ItemType { KEY, CONSUMABLE, INSPECTABLE, TOOL, COOLDOWN_TOOL, CLOTHING, LAMP} 
@export var item_type: ItemType = ItemType.KEY

@export var document_image: Texture2D = null  # L'image du parchemin/document
@export var document_text: String = ""         # Le texte affiché par dessus

# Consommables
@export var health_effect: float = 0.0  # positif = soin, négatif = dégât

# Outils
@export var tool_damage: float = 0.0          # Dégâts infligés aux ennemis
@export var tool_required_id: String = ""      # ID requis sur la cible (ex: "planche", "arbre")
@export var tool_swing_duration: float = 0.6   # Durée du swing
@export var tool_animations: Dictionary = {
	"stand": "swing",    # Animation debout par défaut
	"crouch": "swing"    # Animation accroupi (même par défaut, à changer)
}
@export_group("Hand Offset")
@export var hand_position_offset: Vector3 = Vector3.ZERO
@export var hand_rotation_offset: Vector3 = Vector3.ZERO

@export var cooldown_duration: float = 3.0 

# ───────────────────────────── HABIT (CLOTHING) ─────────────────────────────
@export_group("Habit (Clothing)")
## MeshInstance3D (enfants du Skeleton3D, groupe "OutfitMesh") à rendre visibles
## quand cet habit est porté. Glissez les nœuds depuis l'arbre de scène du joueur.
@export var clothing_mesh_node_paths: Array[String] = []

@export var show_civilian_with_clothing: bool = false
@export var heavy_diving_suit: bool = false

## Secondes d'apnée supplémentaires, ajoutées à l'autonomie de base
@export var oxygen_bonus: float = 0.0

## Multiplicateur appliqué à (base + bonus). 1.0 = pas de changement, 2.0 = double autonomie
@export var oxygen_multiplier: float = 1.0
