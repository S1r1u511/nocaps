extends SceneTree

## Wallet links from the platform (platform/wallet_link.gd + embed inbound):
## only allowed origins are heard, and a link must name this player and wallet.
##   scripts/run_tests.sh wallet_link_smoke

const TestEnv := preload("res://tests/test_env.gd")
const ADDR := "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
const SIG := "5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW"

func _initialize() -> void:
	call_deferred("run")

func _message(player: String, address: String) -> String:
	var text := "play.nocaps.fun wants you to sign in with your Solana account:\n%s\n\nURI: https://play.nocaps.fun\nNonce: abc\nResources:\n- nocaps:player:%s" % [address, player]
	return Marshalls.utf8_to_base64(text)

func run() -> void:
	if not TestEnv.begin("wallet_link_smoke"):
		return
	var ok := {"address": ADDR, "signature": SIG, "message": _message("uid123", ADDR), "method": "wallet"}
	assert(WalletLink.problem(ok, "uid123") == "", "a well-formed link passes: %s" % WalletLink.problem(ok, "uid123"))
	assert(WalletLink.problem(ok, "someoneElse") == "message_player_mismatch", "a link for another player is refused")
	assert(WalletLink.problem(ok, "guest-local") == "not_signed_in", "offline guests can't link")
	var other := ok.duplicate()
	other["message"] = _message("uid123", "9" + ADDR.substr(1))
	assert(WalletLink.problem(other, "uid123") == "message_wallet_mismatch", "the signed text must name the wallet")
	var bad := ok.duplicate()
	bad["address"] = "0OIl" + ADDR.substr(4)
	assert(WalletLink.problem(bad, "uid123") == "bad_address", "non-base58 address")
	bad = ok.duplicate()
	bad["method"] = "email"
	assert(WalletLink.problem(bad, "uid123") == "bad_method", "unknown method")

	assert(EmbedService.is_platform_origin("https://play.nocaps.fun"), "production platform")
	assert(EmbedService.is_platform_origin("http://localhost:3000"), "local dev")
	assert(EmbedService.is_platform_origin("https://nocaps-web-git-feat-x-s1r1u511.vercel.app"), "vercel preview")
	assert(not EmbedService.is_platform_origin("https://evil.example"), "other sites")
	assert(not EmbedService.is_platform_origin("https://play.nocaps.fun.evil.example"), "lookalike host")

	var heard: Array = []
	EmbedService.listen(func(d: Dictionary) -> void: heard.append(d))
	EmbedService.receive({"type": "nocaps-link-wallet"}, "https://evil.example")
	EmbedService.receive("not a dict", "https://play.nocaps.fun")
	EmbedService.receive({"type": "other"}, "https://play.nocaps.fun")
	assert(heard.is_empty(), "foreign or malformed messages are ignored")
	EmbedService.receive({"type": "nocaps-link-wallet"}, "https://play.nocaps.fun")
	assert(heard.size() == 1, "platform messages are delivered")
	EmbedService.listen(Callable())

	# The app's MWA sign-in names the player once it is known.
	var wallet: Node = load("res://platform/wallet_service.gd").new()
	assert(not wallet.sign_in_statement().contains("nocaps:player:"), "no player yet: plain statement")
	wallet.player_hint = "uid123"
	assert(wallet.sign_in_statement().ends_with("nocaps:player:uid123"), "statement names the player")
	wallet.free()
	print("WALLET_LINK_PASS: origins filtered, links bound to player + wallet")
	quit()
