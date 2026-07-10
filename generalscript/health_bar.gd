# HealthBar.gd
extends Control

@onready var health_bar: ProgressBar = $VBoxContainer/HealthProgressBar
#@onready var health_label: Label = $VBoxContainer/HealthLabel

func update(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	#health_label.text = "PV : %d / %d" % [current, maximum]
