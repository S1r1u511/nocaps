extends SceneTree

## Lazy roster: Home can list every community (id, name, color, order) without
## loading any mascot/cap texture, and a shown community's art loads on demand.
##   scripts/run_tests.sh roster_lazy_smoke

const TestEnv := preload("res://tests/test_env.gd")
const MERT_MASCOT := "res://assets/communities/mert/mascot.png"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("roster_lazy_smoke"):
		return
	CommunityRepository.clear_lite_roster()
	assert(not ResourceLoader.has_cached(MERT_MASCOT),
		"no community mascot should be cached at test start")

	var lite := CommunityRepository.load_roster_lite()
	assert(lite != null and lite.communities.size() >= 5, "the lite roster lists every community")
	for community in lite.communities:
		assert(community.mascot == null, "listing must not load mascot art (%s)" % community.id)
		assert(community.cap == null, "listing must not load cap art (%s)" % community.id)
		assert(not community.display_name.is_empty(), "lite community keeps its display name")
	assert(not ResourceLoader.has_cached(MERT_MASCOT),
		"listing the roster must not load any community texture")

	# The real Home: setup lists the roster and schedules art for the next frame.
	# Before that frame, no community texture may be loaded.
	CommunityRepository.clear_lite_roster()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	assert(not ResourceLoader.has_cached(MERT_MASCOT),
		"Home setup must not load a community texture before its first frame")
	await process_frame
	await process_frame
	assert(ResourceLoader.has_cached(MERT_MASCOT),
		"Home art is loaded on the frame after the first paint")
	main.queue_free()
	await process_frame

	var first: CommunityDefinition = lite.communities[0]
	assert(first.id == &"mert", "roster order is preserved (mert first)")
	assert(CommunityRepository.ensure_art(first), "ensure_art loads a shown community's art")
	assert(first.mascot != null and first.mascot.idle_texture != null,
		"the shown community gets its mascot")
	assert(ResourceLoader.has_cached(MERT_MASCOT), "the shown community's texture is now loaded")

	# The eager roster used by the run still carries art.
	var eager := CommunityRepository.load_roster()
	assert(eager != null and eager.communities.size() >= 5, "the eager roster still loads")
	var has_art := false
	for community in eager.communities:
		if community.mascot != null and community.mascot.idle_texture != null:
			has_art = true
	assert(has_art, "the eager roster keeps its art for the run")

	CommunityRepository.clear_lite_roster()
	print("ROSTER_LAZY_PASS: roster lists without textures, art loads on demand")
	quit()
