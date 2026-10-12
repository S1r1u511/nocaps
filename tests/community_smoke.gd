extends SceneTree

## Phase 3.5 smoke test: the authored roster resolves, defaults fall back correctly,
## and the content-relative fit math is sane. Run with:
##   scripts/run_tests.sh community_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("community_smoke"):
		return
	var roster := CommunityRepository.load_roster()
	assert(roster != null, "roster failed to load")

	var enabled := CommunityRepository.enabled_sorted(roster)
	assert(enabled.size() == 5, "expected 5 enabled communities, got %d" % enabled.size())
	assert(enabled[0].id == &"mert", "first community should be mert by sort order")
	assert(enabled[1].id == &"wif", "second community should be wif")
	assert(enabled[2].id == &"bitsy", "third community should be bitsy")
	assert(enabled[3].id == &"mole", "fourth community should be mole")
	assert(enabled[4].id == &"solcity", "fifth community should be solcity")

	# Selection resolution and fallback.
	assert(CommunityRepository.resolve_selected(roster, &"wif").id == &"wif", "explicit selection not honored")
	assert(CommunityRepository.resolve_selected(roster, &"missing").id == &"mert", "fallback selection wrong")
	assert(CommunityRepository.resolve_selected(roster, &"").id == &"mert", "empty selection should fall back to first enabled")

	# Rivals exclude the target.
	var target := CommunityRepository.resolve_selected(roster, &"mert")
	var rivals := CommunityRepository.rivals_for(roster, target)
	assert(rivals.size() == 4, "rivals should be the four other communities")
	var rival_ids: Array[StringName] = []
	for rival in rivals:
		rival_ids.append(rival.id)
	assert(
		rival_ids.has(&"wif") and rival_ids.has(&"bitsy")
			and rival_ids.has(&"mole") and rival_ids.has(&"solcity"),
		"rival ids should be wif, bitsy, mole, and solcity"
	)

	# The Mole crew ships its own helmet cap.
	var mole := CommunityRepository.resolve_selected(roster, &"mole")
	assert(mole != null and mole.mascot != null and mole.mascot.idle_texture != null, "mole mascot art missing")
	assert(mole.cap != null and mole.cap.side_texture != null, "mole cap missing")

	# SolanaCity ships its own cap art, links, and a fitted mascot.
	var solcity := CommunityRepository.resolve_selected(roster, &"solcity")
	assert(solcity != null and solcity.mascot != null and solcity.mascot.idle_texture != null, "solcity mascot art missing")
	assert(solcity.cap != null and solcity.cap.side_texture != null and solcity.cap.center_texture != null, "solcity cap missing")
	assert(solcity.social_url(&"x") == "https://x.com/PlaySolCity", "solcity X link wrong")
	assert(solcity.social_url(&"website") == "https://www.solanacity.io", "solcity website link wrong")
	assert(solcity.mascot.cap_scale > 0.0, "solcity cap fit must be authored")

	# Cap and background fall back to the shared defaults when the community has none.
	var cap := CommunityRepository.resolve_cap(target)
	assert(cap != null and cap.side_texture != null and cap.center_texture != null, "default cap fallback failed")
	var background := CommunityRepository.resolve_background(target)
	assert(background != null, "default background fallback failed")

	# Content-relative fit math for the textured target.
	var mascot: MascotDefinition = target.mascot
	assert(mascot != null and mascot.idle_texture != null, "mert mascot art missing")
	var content := MascotFit.content_bounds(mascot.idle_texture).size
	assert(content.x > 0.0 and content.y > 0.0, "mascot content bounds are empty")
	var scale := MascotFit.scale_for(content, 180.0)
	assert(is_equal_approx(maxf(content.x, content.y) * scale, 180.0), "world-size scaling wrong")
	assert(is_equal_approx(MascotFit.head_center_x(mascot, content, scale), 0.0), "centered head band should be at x=0")
	assert(MascotFit.head_half_width(mascot, content, scale) > 0.0, "head half width must be positive")
	assert(MascotFit.head_depth(mascot, content, scale) > 0.0, "head band depth must be positive")

	print("COMMUNITY_PASS: roster, fallbacks, and fit math verified")
	quit()
