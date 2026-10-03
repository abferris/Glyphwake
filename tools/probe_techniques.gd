extends SceneTree

## Probe: does the Player scene's glyph runtime resolve? Prints each reference.

var p: Node
var t := 0


func _initialize() -> void:
	p = (load("res://Scenes/Player.tscn") as PackedScene).instantiate()
	root.call_deferred("add_child", p)


func _physics_process(_delta: float) -> bool:
	t += 1
	if t < 4:
		return false
	print("controller.Techniques: ", p.Techniques)
	print("node Techniques: ", p.get_node_or_null("Techniques"))
	print("node Loadout: ", p.get_node_or_null("Loadout"))
	print("node Resources: ", p.get_node_or_null("Resources"))
	var tn: Node = p.get_node_or_null("Techniques")
	if tn != null:
		print("  .Technique: ", tn.Technique)
		print("  .Loadout: ", tn.Loadout)
		print("  .Resources: ", tn.Resources)
		print("  TryAirJump(0, 1.5) -> ", tn.TryAirJump(0, 1.5))
		var l: Node = tn.Loadout
		if l != null:
			print("  Loadout.Entries: ", l.Entries.size(), " PointsFor: ", l.PointsFor(tn.Technique))
		var r: Node = tn.Resources
		if r != null:
			print("  Resources.Mana: ", r.Mana)
	quit(0)
	return true
