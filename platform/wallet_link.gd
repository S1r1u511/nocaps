extends RefCounted
class_name WalletLink

## Shape checks for a wallet link the platform sends into the embedded game
## (nocaps-link-wallet). The ed25519 signature itself is verified server-side /
## at payout; here we only make sure the signed text names this player and
## this wallet, so a link can't be replayed onto someone else.

const BASE58 := "^[1-9A-HJ-NP-Za-km-z]+$"

static func _base58(value: String, min_len: int, max_len: int) -> bool:
	return value.length() >= min_len and value.length() <= max_len \
		and RegEx.create_from_string(BASE58).search(value) != null

## Empty when OK, otherwise a short reason.
static func problem(data: Dictionary, player_id: String) -> String:
	if player_id.is_empty() or player_id == "guest-local":
		return "not_signed_in"
	var address := String(data.get("address", ""))
	var message := String(data.get("message", ""))
	var signature := String(data.get("signature", ""))
	var method := String(data.get("method", "wallet"))
	if not _base58(address, 32, 44):
		return "bad_address"
	if not _base58(signature, 64, 100):
		return "bad_signature"
	if method != "wallet" and method != "privy":
		return "bad_method"
	if message.is_empty() or message.length() > 1500:
		return "bad_message"
	var text := Marshalls.base64_to_utf8(message)
	if not text.contains(address):
		return "message_wallet_mismatch"
	if not text.contains("nocaps:player:%s" % player_id):
		return "message_player_mismatch"
	return ""
