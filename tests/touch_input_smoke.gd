extends SceneTree

## Touch/GUI routing smoke test: a touch at mid-screen must reach the run's
## gameplay (cap flaps), i.e. no UI/background Control swallows it. Also checks the
## pause overlay. Run with:
##   scripts/run_tests.sh touch_input_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("touch_input_smoke"):
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var flow := main.get_node("AppFlow") as AppFlow
	assert(flow != null, "AppFlow missing")
	flow.transitions_enabled = false
	flow.go_to(&"run", {})
	await process_frame
	var run := flow.current_screen()
	assert(run != null and run.name == "Run", "run did not load")

	run.set_process(false)
	run.cap.velocity_y = 0.0
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(360.0, 640.0)
	root.push_input(touch)
	await process_frame
	assert(run.cap.velocity_y < 0.0, "touch did not reach gameplay (cap did not flap)")

	run._pause()
	assert(run._paused and run.pause_overlay.visible, "pause overlay did not open")
	run._resume()
	assert(not run._paused and not run.pause_overlay.visible, "pause overlay did not close")

	main.queue_free()
	await process_frame
	print("TOUCH_PASS: taps reach gameplay; pause overlay works")
	quit()
