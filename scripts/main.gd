extends Node2D
## Cảnh chính: ghép bản đồ, giao diện và màn trận đánh.

const MapView = preload("res://scripts/map_view.gd")
const UI = preload("res://scripts/ui.gd")
const BattleView = preload("res://scripts/battle_view.gd")

var map_view
var ui
var battle


func _ready() -> void:
	map_view = MapView.new()
	add_child(map_view)
	battle = BattleView.new()
	add_child(battle)
	ui = UI.new()
	add_child(ui)
	ui.map_view = map_view
	ui.battle = battle
	ui.setup()
	map_view.tile_tapped.connect(ui.on_tile_tapped)
	battle.finished.connect(ui.on_battle_finished)
