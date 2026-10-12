extends Node
class_name AppFlow

## Minimal app router for the v1 shell with a quick fade transition between
## screens. Screens expose `navigate(screen, payload)` and optionally
## `setup(payload)` / `bind_services(save, backend)`; they never know about one
## another. Deliberately not a global autoload.

const SCREENS := {
	&"home": "res://scenes/ui/home_screen.tscn",
	&"community_select": "res://scenes/ui/community_select_screen.tscn",
	&"community_detail": "res://scenes/ui/community_detail_screen.tscn",
	&"community_editor": "res://scenes/ui/community_editor_screen.tscn",
	&"run": "res://scenes/run.tscn",
	&"result": "res://scenes/ui/result_screen.tscn",
	&"leaderboard": "res://scenes/ui/leaderboard_screen.tscn",
	&"profile": "res://scenes/ui/profile_screen.tscn",
	&"quests": "res://scenes/ui/quests_screen.tscn",
}

@export var start_screen: StringName = &"home"
@export var screen_container_path: NodePath = ^"../ScreenContainer"
@export var save_manager_path: NodePath = ^"../SaveManager"
@export var backend_client_path: NodePath = ^"../BackendClient"
@export var shell_path: NodePath = ^"../Shell"

@onready var container: Control = get_node(screen_container_path) as Control
@onready var save_manager: SaveManager = get_node_or_null(save_manager_path) as SaveManager
@onready var backend_client: BackendClient = get_node_or_null(backend_client_path) as BackendClient
@onready var shell: ShellUI = get_node_or_null(shell_path) as ShellUI

var _current: Node = null
var _fade: ColorRect
var _first: bool = true
var _busy: bool = false

## Disable for headless tests that navigate rapidly.
var transitions_enabled: bool = true

func _ready() -> void:
	_create_fade()
	_apply_settings()
	if shell != null:
		shell.bind_app(self)
	if EmbedService.is_embedded():
		_start_embedded()
		return
	_bind_app_wallet()
	var deep_link := InviteService.accept_deep_link(save_manager, InviteService.deep_link_crew_id())
	if deep_link != &"":
		go_to(&"community_detail", {"community_id": deep_link})
	else:
		go_to(start_screen)
	call_deferred("_drain_submissions")
	call_deferred("_warm_standings")
	call_deferred("_check_app_version")

## App wallet sign-in (Android MWA) joins the daily prize board the same way the
## web platform does: the sign-in names this player and is stored in wallet_links.
func _bind_app_wallet() -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null or backend_client == null:
		return
	backend_client.signed_in.connect(func(id: String) -> void: wallet.set("player_hint", id))
	# If the anonymous sign-in already finished before this ran, the signal above
	# never fires: seed the hint now, or the wallet sign-in would not name this
	# player and the link would be refused ("Reconnect your wallet…").
	var current := String(backend_client.get("player_id"))
	if not current.is_empty():
		wallet.set("player_hint", current)
	if wallet.has_signal("message_signed"):
		wallet.connect("message_signed", _on_app_wallet_signed)
	if wallet.has_signal("wallet_error"):
		wallet.connect("wallet_error", _on_app_wallet_error)

## Wallet failures used to be silent (Oct 10): say what happened, never crash.
func _on_app_wallet_error(code: String, detail: String) -> void:
	match code:
		"no_wallet":
			Toasts.show_message("Install a Solana wallet (like Phantom) to connect")
		"cancelled":
			Toasts.show_message("Wallet connection cancelled")
		"timeout":
			Toasts.show_message("The wallet didn't answer in time. Try again")
		"unknown" when detail.to_lower().contains("association"):
			Toasts.show_message("Couldn't reach your wallet. Open Phantom once, then try again")
		"unavailable":
			Toasts.show_message("Wallets aren't available on this device")
		_:
			Toasts.show_message("Couldn't connect your wallet. Try again")

func _on_app_wallet_signed(message: String, signature: String) -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null or backend_client == null or not backend_client.is_available():
		print("NOCAPS wallet: link skipped (backend unavailable)")
		Toasts.show_message("You're offline. Connect your wallet again when you're back online")
		return
	var data := {
		"address": String(wallet.get("wallet_address")),
		"message": Marshalls.utf8_to_base64(message),
		"signature": signature,
		"method": "wallet",
	}
	var problem := WalletLink.problem(data, backend_client.player_id)
	print("NOCAPS wallet: link check uid=%s problem=%s" % [backend_client.player_id, problem if not problem.is_empty() else "none"])
	if problem == "message_player_mismatch" or problem == "not_signed_in":
		Toasts.show_message("Still signing in. Disconnect and connect your wallet again in a moment")
		return
	if not problem.is_empty():
		Toasts.show_message("Couldn't verify your wallet (%s). Try again" % problem)
		return
	print("NOCAPS wallet: sending to linkWallet")
	backend_client.link_wallet_async(String(data["address"]), String(data["message"]), signature, "wallet",
		PlayerName.board_name(save_manager), func(result: Dictionary) -> void:
			print("NOCAPS wallet: linkWallet result ok=%s error=%s" % [str(result.get("ok", false)), String(result.get("error", ""))])
			if bool(result.get("ok", false)):
				if save_manager != null:
					save_manager.verified_wallet = String(data["address"])
					save_manager.save_data()
				Toasts.show_message("Wallet verified · you're prize-eligible")
				var w := get_node_or_null("/root/WalletService")
				if w != null and w.has_method("_refresh_profile"):
					w.call("_refresh_profile")
			elif String(result.get("error", "")) == "offline":
				Toasts.show_message("You're offline. Connect your wallet again when you're back online")
			else:
				Toasts.show_message("Couldn't verify your wallet (%s). Try again" % String(result.get("error", "error"))))

## Platform embed (platform/embed_service.gd): the platform owns home, crews and
## boards, so the game goes straight to a run for the requested crew. The crew
## the platform asked for always wins (it is what the player picked there).
func _start_embedded() -> void:
	# A name picked on the platform becomes the board name (skips the in-game prompt).
	var name := EmbedService.player_name()
	if save_manager != null and PlayerName.is_valid(name) and save_manager.display_name != name:
		save_manager.display_name = name
		save_manager.save_data()
	var crew := EmbedService.crew_id()
	var community := CommunityRepository.by_id(CommunityRepository.load_roster(), crew)
	if save_manager != null and community != null and community.enabled:
		save_manager.set_selected_community(crew)
	EmbedService.listen(_on_platform_message)
	if backend_client != null:
		backend_client.signed_in.connect(func(id: String) -> void:
			EmbedService.player(id, PlayerName.board_name(save_manager)))
	go_to(&"run")
	call_deferred("_drain_submissions")
	call_deferred("_warm_standings")

## Inbound platform requests while embedded (docs/EMBED.md).
func _on_platform_message(data: Dictionary) -> void:
	match String(data.get("type", "")):
		"nocaps-link-wallet":
			link_wallet_from_platform(data)
		"nocaps-battle":
			EmbedService.set_battle(data)

## Validates a wallet link from the platform and stores it for this player.
func link_wallet_from_platform(data: Dictionary) -> void:
	var problem := WalletLink.problem(data, String(backend_client.get("player_id")) if backend_client != null else "")
	if not problem.is_empty():
		EmbedService.post("nocaps-wallet-failed", {"reason": problem})
		return
	var address := String(data["address"])
	backend_client.link_wallet_async(address, String(data["message"]), String(data["signature"]),
		String(data.get("method", "wallet")), PlayerName.board_name(save_manager),
		func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				EmbedService.post("nocaps-wallet-linked", {"address": address})
			else:
				EmbedService.post("nocaps-wallet-failed", {"reason": String(result.get("error", "save_failed"))}))

## Screens the platform shows itself while embedded: leave the game instead.
const EMBED_EXITS := {&"leaderboard": "board"}

## Starts the first standings fetch at boot (after cached rows are on disk), so the
## board is already populated by the time the player opens it.
func _warm_standings() -> void:
	Standings.warm_up(backend_client)
	BattleService.refresh(true)

## Drains queued runs once services are ready; failures stay queued with backoff.
func _drain_submissions() -> void:
	if save_manager == null or backend_client == null or not backend_client.is_available():
		return
	backend_client.sign_in_guest()
	RunSubmission.flush_async(save_manager, backend_client, func(summary: Dictionary) -> void:
		var submitted := int(summary.get("submitted", 0))
		if submitted <= 0:
			return
		var personal := int(summary.get("personal", 0))
		var counted := submitted - personal
		if counted > 0:
			Toasts.show_message("%d offline run%s added to today's board" % [counted, "" if counted == 1 else "s"])
		if personal > 0:
			Toasts.show_message("%d run%s from earlier days saved as personal scores" % [personal, "" if personal == 1 else "s"])
		if shell != null:
			shell.refresh())

func _create_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 64
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.04, 0.03, 0.09, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)

func go_to(screen: StringName, payload: Dictionary = {}) -> void:
	if _busy:
		return
	if EmbedService.is_embedded() and screen != &"run" and screen != &"result":
		EmbedService.exit(EMBED_EXITS.get(screen, "home"))
		return
	if _first or not transitions_enabled:
		_first = false
		_swap(screen, payload)
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var out := create_tween()
	out.tween_property(_fade, "modulate:a", 1.0, 0.10)
	await out.finished
	_swap(screen, payload)
	var back := create_tween()
	back.tween_property(_fade, "modulate:a", 0.0, 0.16)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false

func _swap(screen: StringName, payload: Dictionary) -> void:
	if screen == &"run":
		BattleService.refresh()
	if screen == &"result":
		_on_run_finished(payload)
		if EmbedService.is_embedded():
			var player := String(backend_client.get("player_id")) if backend_client != null else ""
			EmbedService.run_finished(payload, player, PlayerName.board_name(save_manager))
	var path: String = SCREENS.get(screen, "")
	if path.is_empty():
		push_error("AppFlow: unknown screen '%s'" % screen)
		return

	if _current != null and is_instance_valid(_current):
		container.remove_child(_current)
		_current.queue_free()
		_current = null

	var scene := load(path) as PackedScene
	if scene == null:
		push_error("AppFlow: cannot load screen scene '%s'" % path)
		return

	var instance := scene.instantiate()
	container.add_child(instance)
	_current = instance

	if _current.has_signal("navigate"):
		_current.connect("navigate", Callable(self, "go_to"))
	if _current.has_method("bind_services"):
		_current.call("bind_services", save_manager, backend_client)
	if _current.has_method("setup"):
		_current.call("setup", payload)
	if _current.has_method("play_intro"):
		_current.call("play_intro")
	if shell != null:
		shell.set_screen(screen)

## Run-finished hook: the run payload feeds quest progress (docs/15 §4). Guarded
## so non-run result navigations (captures/tests) never advance quests.
func _on_run_finished(payload: Dictionary) -> void:
	if save_manager == null:
		return
	if not payload.has("community_id") and not payload.has("score"):
		return
	Quests.record_run(save_manager, payload)

## Push persisted player settings into the audio/haptics services at boot.
func _apply_settings() -> void:
	if save_manager == null:
		return
	var sound := get_node_or_null("/root/SoundService")
	if sound != null:
		sound.set("is_sound_enabled", not save_manager.muted)
	Haptics.enabled = save_manager.haptics_enabled

## The screen currently displayed, or null during a transition.
func current_screen() -> Node:
	return _current

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		BattleService.refresh_if_stale(20000)
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var screen := current_screen()
		var screen_name: String = String(screen.name) if screen != null else ""
		if screen_name == "Run":
			return  # the run handles back as pause/resume
		if screen_name == "HomeScreen":
			get_tree().quit()
		else:
			go_to(&"home", {})

## --- Version check (Oct 10, fundamentals E2) -----------------------------------
## One read of `config/app` per launch. Below `minVersion` the app is blocked with
## an update screen, so players never hit silent backend rejections after a rules
## change. A newer `latestVersion` only shows a toast. Offline: no gate.
func _check_app_version() -> void:
	if backend_client == null or not backend_client.is_available() or EmbedService.is_embedded():
		return
	backend_client.fetch_app_config_async(func(config: Dictionary) -> void:
		if not bool(config.get("ok", false)):
			return
		if AppVersion.is_below(String(config.get("minVersion", ""))):
			_show_update_required(String(config.get("message", "")), String(config.get("updateUrl", "")))
		elif not String(config.get("latestVersion", "")).is_empty() \
				and AppVersion.compare(AppVersion.semver(), String(config["latestVersion"])) < 0:
			Toasts.show_message("A new NOCAPS version is available"))

func _show_update_required(message: String, url: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "UpdateRequired"
	layer.layer = 100
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.09, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	box.custom_minimum_size = Vector2(560, 0)
	center.add_child(box)
	var title := Label.new()
	title.text = "Update NOCAPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)
	var body := Label.new()
	body.text = message if not message.is_empty() else "This version is too old to join the live boards. Get the latest build to keep playing for your crew."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 26)
	box.add_child(body)
	if not url.is_empty():
		var button := Button.new()
		button.text = "Get the update"
		button.custom_minimum_size = Vector2(0, 88)
		button.add_theme_font_size_override("font_size", 30)
		button.pressed.connect(func() -> void: OS.shell_open(url))
		box.add_child(button)
