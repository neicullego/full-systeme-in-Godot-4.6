class_name SkinData
extends Resource

@export var skin_id: String = ""
@export var skin_name: String = ""
@export var preview_image: Texture2D = null
## Meshes à afficher pour ce skin (mêmes règles que les habits :
## enfants du Skeleton3D, groupe "OutfitMesh" obligatoire)
@export var skin_mesh_node_paths: Array[String] = []
