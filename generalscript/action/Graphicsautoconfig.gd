extends Node
## Autoload : GraphicsAutoConfig
##
## Rôle volontairement limité : DÉTECTER le matériel du joueur et PROPOSER un
## Dictionary de réglages recommandés. Ce script n'applique ni ne sauvegarde
## rien lui-même — c'est settings.gd (le vrai gestionnaire de réglages du
## jeu) qui reste l'unique responsable d'appliquer/sauvegarder, pour éviter
## que deux systèmes ne se contredisent sur les mêmes réglages.
##
## Mise en place : Project > Project Settings > Autoload
## -> ajouter ce script, nom du singleton "GraphicsAutoConfig", cocher Enable.
##
## Utilisation typique (depuis settings.gd) :
##   var tier = GraphicsAutoConfig.detect_hardware_tier()
##   var recommended = GraphicsAutoConfig.get_recommended_settings(tier)
##   for key in recommended.keys():
##       current_settings[key] = recommended[key]

enum Tier { LOW = 0, MEDIUM = 1, HIGH = 2 }

## Sous-ensemble de réglages "graphiques" par palier. Les clés correspondent
## exactement à celles de `current_settings` dans settings.gd. Seuls les
## réglages liés aux performances sont ici : le volume, la sensibilité de la
## caméra, le mode fenêtré, le micro, etc. restent un choix personnel du
## joueur et ne sont jamais touchés par la détection auto.
const RECOMMENDED_PRESETS := {
	Tier.LOW: {
		"glow": false,
		"ssil": false,
		"ssao": false,
		"ssr": false,
		"sdfgi": false,
		"ao_quality": 0,
		"shadows": 1,
		"scale_3d": 0.75,
		"fps_cap": 1,   # 60 fps
		"vsync": true,
	},
	Tier.MEDIUM: {
		"glow": true,
		"ssil": false,
		"ssao": true,
		"ssr": false,
		"sdfgi": false,
		"ao_quality": 2,
		"shadows": 3,
		"scale_3d": 1.0,
		"fps_cap": 1,   # 60 fps
		"vsync": true,
	},
	Tier.HIGH: {
		"glow": true,
		"ssil": true,
		"ssao": true,
		"ssr": true,
		"sdfgi": true,
		"ao_quality": 4,
		"shadows": 5,
		"scale_3d": 1.0,
		"fps_cap": 2,   # illimité
		"vsync": true,
	},
}


# ---------------------------------------------------------------------------
# Détection matérielle
# ---------------------------------------------------------------------------

## Retourne Tier.LOW / Tier.MEDIUM / Tier.HIGH selon un score heuristique
## basé sur le CPU, la RAM et le GPU de la machine.
func detect_hardware_tier() -> int:
	# Mobile/Web : on reste volontairement prudent par défaut.
	var platform := OS.get_name()
	if platform == "Android" or platform == "iOS" or platform == "Web":
		return Tier.LOW

	var score := 0

	# --- CPU : nombre de coeurs logiques ---
	var cores := OS.get_processor_count()
	if cores >= 8:
		score += 2
	elif cores >= 4:
		score += 1

	# --- RAM physique disponible ---
	var mem := OS.get_memory_info()
	var physical_bytes: int = mem.get("physical", -1)
	if physical_bytes > 0:
		var ram_gb := float(physical_bytes) / (1024.0 * 1024.0 * 1024.0)
		if ram_gb >= 16.0:
			score += 2
		elif ram_gb >= 8.0:
			score += 1

	# --- GPU : type (dédié/intégré) + nom ---
	var gpu_type := RenderingServer.get_video_adapter_type()
	if gpu_type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		score += 1

	score += _score_from_gpu_name(RenderingServer.get_video_adapter_name().to_lower())

	if score >= 5:
		return Tier.HIGH
	elif score >= 2:
		return Tier.MEDIUM
	else:
		return Tier.LOW


## Heuristique texte sur le nom du GPU. Volontairement prudente : en cas de
## doute (carte inconnue) on ne donne ni bonus ni malus.
func _score_from_gpu_name(name: String) -> int:
	var high_end := ["rtx 50", "rtx 40", "rtx 30", "rtx 20", "rx 9", "rx 7", "rx 6", "arc a7"]
	var low_end := ["uhd graphics", "hd graphics", "iris", "vega 3", "vega 6", "mx150", "mx250", "mx330", "mx350"]

	for keyword in high_end:
		if name.find(keyword) != -1:
			return 2
	for keyword in low_end:
		if name.find(keyword) != -1:
			return -1
	if name.find("nvidia") != -1 or name.find("radeon") != -1 or name.find("amd") != -1:
		return 1
	return 0


# ---------------------------------------------------------------------------
# Recommandation (aucun effet de bord, juste de la donnée)
# ---------------------------------------------------------------------------

## Retourne le Dictionary de réglages recommandés pour le palier donné
## (ou celui détecté automatiquement si aucun palier n'est précisé).
func get_recommended_settings(tier: int = -1) -> Dictionary:
	if tier == -1:
		tier = detect_hardware_tier()
	return RECOMMENDED_PRESETS.get(tier, RECOMMENDED_PRESETS[Tier.MEDIUM]).duplicate()


## Pour affichage dans l'UI ("Faible" / "Moyen" / "Élevé").
func get_tier_label(tier: int) -> String:
	match tier:
		Tier.LOW:
			return "Faible"
		Tier.HIGH:
			return "Élevé"
		_:
			return "Moyen"
