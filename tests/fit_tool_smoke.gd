extends SceneTree

## Fit-tool smoke test: the preview builds, and a fit-field change alters both the
## polling signature and the seated-cap position. Run with:
##   scripts/run_tests.sh fit_tool_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("fit_tool_smoke"):
		return
	var tool: Node = load("res://tools/mascot_fit_tool.tscn").instantiate()
	root.add_child(tool)
	await process_frame

	tool.mascot = load("res://data/communities/mert/mascot.tres") as MascotDefinition
	tool.cap = load("res://data/caps/default_cap.tres") as CapDefinition
	await process_frame

	assert(tool._sprite.texture != null, "mascot preview not built")
	assert(tool._cap_sprite.visible, "cap preview should be visible")

	var before: Vector2 = tool._cap_sprite.position
	var signature_before: String = tool._build_signature()

	var mascot: MascotDefinition = tool.mascot
	mascot.cap_anchor = Vector2(0.35, 0.2)
	assert(tool._build_signature() != signature_before, "signature must change when a fit field changes")
	tool._rebuild()
	assert(tool._cap_sprite.position != before, "cap preview did not move after an anchor change")

	mascot.cap_anchor = Vector2(0.5, 0.12)
	tool.free()
	print("FIT_TOOL_PASS: preview rebuilds on fit changes")
	quit()
