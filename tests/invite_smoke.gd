extends SceneTree

## Invite smoke test: canonical link/share text, `?crew=` query parsing, and the
## deep-link boot policy (pre-select only when nothing is selected; unknown or
## disabled ids ignored; an existing selection is never overridden).
##   scripts/run_tests.sh invite_smoke

const TestEnv := preload("res://tests/test_env.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not TestEnv.begin("invite_smoke"):
		return
	var roster := CommunityRepository.load_roster()
	var wif := CommunityRepository.by_id(roster, &"wif")
	assert(wif != null, "wif missing from roster")

	assert(InviteService.link(wif) == "https://play.nocaps.fun/?crew=wif", "invite link format")
	assert(
		InviteService.share_text(wif) == "Play for Wif on NOCAPS 🧢 https://play.nocaps.fun/?crew=wif",
		"invite share text format"
	)

	assert(InviteService.crew_id_from_query("?crew=wif") == &"wif", "plain query")
	assert(InviteService.crew_id_from_query("crew=wif") == &"wif", "query without ?")
	assert(InviteService.crew_id_from_query("?a=1&crew=wif&b=2") == &"wif", "query among others")
	assert(InviteService.crew_id_from_query("?crew=wi%66") == &"wif", "percent-decoded id")
	assert(InviteService.crew_id_from_query("?crew=wif#frag") == &"wif", "fragment stripped")
	assert(InviteService.crew_id_from_query("?crew=") == &"", "empty id ignored")
	assert(InviteService.crew_id_from_query("?crews=wif") == &"", "similar key ignored")
	assert(InviteService.crew_id_from_query("") == &"", "empty query ignored")

	var save := SaveManager.new()
	assert(InviteService.accept_deep_link(save, &"wif") == &"wif", "valid deep link accepted")
	assert(save.selected_community_id == &"wif", "empty selection is pre-selected")
	save.selected_community_id = &"mert"
	assert(InviteService.accept_deep_link(save, &"wif") == &"wif", "deep link still opens the page")
	assert(save.selected_community_id == &"mert", "existing selection is not overridden")
	assert(InviteService.accept_deep_link(save, &"nope") == &"", "unknown id ignored")
	assert(InviteService.accept_deep_link(save, &"") == &"", "empty id ignored")
	save.free()

	print("INVITE_PASS: link, share text, query parsing, and deep-link policy verified")
	quit()
