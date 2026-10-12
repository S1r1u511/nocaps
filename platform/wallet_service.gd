extends Node

## Wallet boundary for the app. Gameplay and UI only see Godot signals and the
## `wallet_address` string; the Android/Kotlin plugin and Solana Mobile Wallet
## Adapter stay behind this seam.
##
## Wallet policy (hard rules — docs/13_WALLET_MWA_PLAN.md §0): the only wallet
## operations are Sign-In-With-Solana, off-chain signing of a caller-provided
## human-readable message, deauthorize, and (later) read-only public checks.
## No transaction signing/sending, transfers, approvals/delegations, batch or
## blind signing, auto-signing, or background requests. No seed phrases or
## private keys are ever requested, stored, logged, or transmitted, and the full
## auth token is never logged. Every request starts from an explicit user tap.
##
## Android: `connect_wallet()` -> `NocapsWallet` plugin -> MWA Sign-In-With-Solana
## (authorize + sign a human-readable message in one approval) -> the plugin
## emits `wallet_connected(address)` and `wallet_signed(message, signature)`.
## A backend challenge can be signed with `sign_message(challenge)` ->
## MWA `signMessagesDetached` -> `message_signed`.
## Desktop/editor: a local simulator so non-Android debugging still works.
##
## The active Solana cluster comes from the `nocaps/wallet/cluster` project
## setting ("mainnet-beta" now: read-only SIWS sign-in, no transactions or fees);
## nothing hard-codes a cluster.
##
## Failure codes emitted with `wallet_error`: no_wallet, cancelled, timeout,
## unavailable, not_connected, auth, unknown.
##
## See docs/03_ARCHITECTURE.md §9 and docs/13_WALLET_MWA_PLAN.md.

signal wallet_connected(address: String)
signal wallet_disconnected
signal wallet_error(code: String, detail: String)
signal message_signed(message: String, signature: String)

const BRIDGE_NAME := "NocapsWallet"
const SIM_ADDRESS := "NocapsSim1111111111111111111111111111111111"
const CLUSTER_SETTING := "nocaps/wallet/cluster"
const DEFAULT_CLUSTER := "devnet"
const SIGN_IN_DOMAIN := "nocaps.fun"
const SIGN_IN_STATEMENT := "Sign in to NOCAPS to verify this wallet is yours. " \
	+ "This does not move any funds or give NOCAPS access to your assets."

## The anonymous player id; when set, the sign-in statement names it
## (`nocaps:player:<uid>`) so the signature can join that player to the daily
## prize board (wallet_links). Set by AppFlow after backend sign-in.
var player_hint: String = ""

## Short/base58 wallet address, empty when disconnected or guest.
var wallet_address: String = ""

var _bridge: Object = null
var _simulator: bool = false


func _ready() -> void:
	if OS.has_feature("android") and Engine.has_singleton(BRIDGE_NAME):
		_bridge = Engine.get_singleton(BRIDGE_NAME)
		_bridge.wallet_connected.connect(_on_wallet_connected)
		_bridge.wallet_disconnected.connect(_on_wallet_disconnected)
		_bridge.wallet_error.connect(_on_wallet_error)
		_bridge.wallet_signed.connect(_on_wallet_signed)
		wallet_address = String(_bridge.get_wallet_address())
		print("NOCAPS wallet: bridge ready (cluster=%s, address=%s)"
			% [wallet_cluster(), "none" if wallet_address.is_empty() else "restored"])
	elif OS.has_feature("android"):
		push_warning("NOCAPS wallet: Android without a wallet bridge; connect will report unavailable")
	elif not OS.has_feature("web"):
		_simulator = true


func is_available() -> bool:
	return _bridge != null or _simulator


## The configured Solana cluster for wallet operations.
func wallet_cluster() -> String:
	return String(ProjectSettings.get_setting(CLUSTER_SETTING, DEFAULT_CLUSTER))


## Requests wallet sign-in. Completion arrives via `wallet_connected` +
## `message_signed`, or `wallet_error`; this never blocks the game. The wallet
## shows the human-readable sign-in statement before the user approves.
func connect_wallet() -> void:
	if _bridge != null:
		_bridge.connect_wallet(
			SIGN_IN_DOMAIN, sign_in_statement(), _make_nonce(), _issued_at(),
			wallet_cluster(), _make_request_id()
		)
		return
	if _simulator:
		wallet_address = SIM_ADDRESS
		var message := _simulated_sign_in_message(wallet_address, _make_nonce(), _issued_at())
		print("NOCAPS wallet: simulator signed in")
		wallet_connected.emit(wallet_address)
		message_signed.emit(message, "SIMULATED_SIGNATURE")
		_refresh_profile()
		return
	wallet_error.emit("unavailable", "Wallet is not available on this device")


func disconnect_wallet() -> void:
	if _bridge != null:
		_bridge.disconnect_wallet()
		return
	if _simulator and not wallet_address.is_empty():
		wallet_address = ""
		wallet_disconnected.emit()
		_refresh_profile()
		return
	if not _simulator:
		wallet_error.emit("unavailable", "Wallet is not available on this device")


## Asks the wallet to sign a backend-issued challenge string. The signature is
## detached Ed25519 (base58) over the raw UTF-8 message, emitted via
## `message_signed`. Never signs anything but what the caller passes.
func sign_message(message: String) -> void:
	if _bridge != null:
		_bridge.sign_message(message)
		return
	if _simulator:
		message_signed.emit(message, "SIMULATED_SIGNATURE")
		return
	wallet_error.emit("unavailable", "Wallet is not available on this device")


# ---------------------------------------------------------------------------
# Sign-in challenge fields (generated by the app, shown by the wallet)
# ---------------------------------------------------------------------------

func sign_in_statement() -> String:
	if player_hint.is_empty() or player_hint == "guest-local":
		return SIGN_IN_STATEMENT
	return "%s Player: nocaps:player:%s" % [SIGN_IN_STATEMENT, player_hint]


func _make_nonce() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## A fresh per-request id, kept distinct from the nonce (SIWS `requestId`).
func _make_request_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Server clock (Oct 10): the server rejects a sign-in whose Issued At is more than
## 15 minutes away from its own time, so a wrong phone clock must not matter.
func _issued_at() -> String:
	return Time.get_datetime_string_from_unix_time(int(ServerClock.now())) + "Z"


func _simulated_sign_in_message(addr: String, nonce: String, issued_at: String) -> String:
	return "%s wants you to sign in with your Solana account:\n%s\n\n%s\n\nURI: https://%s\nNonce: %s\nIssued At: %s" \
		% [SIGN_IN_DOMAIN, addr, sign_in_statement(), SIGN_IN_DOMAIN, nonce, issued_at]


# ---------------------------------------------------------------------------
# Bridge callbacks
# ---------------------------------------------------------------------------

func _on_wallet_connected(address: String) -> void:
	wallet_address = address
	print("NOCAPS wallet: connected")
	wallet_connected.emit(address)
	_refresh_profile()


func _on_wallet_disconnected() -> void:
	wallet_address = ""
	print("NOCAPS wallet: disconnected")
	wallet_disconnected.emit()
	_refresh_profile()


func _on_wallet_error(code: String, detail: String) -> void:
	push_warning("NOCAPS wallet: %s (%s)" % [code, detail])
	wallet_error.emit(code, detail)


func _on_wallet_signed(message: String, signature: String) -> void:
	print("NOCAPS wallet: signed message (signature=%s)" % signature)
	message_signed.emit(message, signature)


# ---------------------------------------------------------------------------
# UI refresh
# ---------------------------------------------------------------------------

## Rebuilds the Profile screen in place after a wallet state change. The Profile
## card reads `wallet_address` at build time, so the connect/disconnect buttons
## need this to repaint. Does nothing when another screen is showing.
func _refresh_profile() -> void:
	var shell := ShellUI.instance
	if shell == null or shell.app == null:
		return
	var app: Node = shell.app
	if not app.has_method("current_screen"):
		return
	var screen: Variant = app.call("current_screen")
	if screen != null and String(screen.name) == "ProfileScreen" and screen.has_method("_rebuild"):
		screen.call("_rebuild")
