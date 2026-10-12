/**
 * Wallet link verification (Oct 10, fundamentals D2/D3). Pure functions, unit
 * tested in test/wallet.test.js.
 *
 * The app signs in with Mobile Wallet Adapter "Sign In With Solana": ONE wallet
 * approval returns the signed SIWS message (UTF-8 text) and a detached Ed25519
 * signature (base58). The server accepts the link only when:
 *  - the signature verifies against the claimed public key over the exact text;
 *  - the text names this Firebase uid ("nocaps:player:<uid>") and this address;
 *  - the text is a SIWS message for an allowed domain;
 *  - "Issued At" is within ISSUED_AT_WINDOW_MS of server time (no old replays).
 * Binding the uid + freshness replaces a server nonce: a replayed message can
 * only ever re-link the same wallet to the same player, within minutes.
 */
const nacl = require("tweetnacl");

const ALLOWED_DOMAINS = ["nocaps.fun"];
const ISSUED_AT_WINDOW_MS = 15 * 60 * 1000;
const MAX_MESSAGE = 2000;
const BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

// Mirrors core/player_name.gd and the rules' player_name_ok().
const BLOCKED = /(fuck|shit|bitch|cunt|nigg|fag|rape|nazi|hitler|porn|slut|whore|retard|kys|admin|nocaps_team|moderator)/;
function playerNameOk(name) {
	if (typeof name !== "string") return false;
	if (/^Guest [0-9]{4}$/.test(name)) return true;
	const lower = name.toLowerCase();
	return /^[A-Za-z0-9_]{3,16}$/.test(name) && !lower.startsWith("guest") && !BLOCKED.test(lower);
}

function base58Decode(text) {
	if (typeof text !== "string" || text.length === 0) throw new Error("invalid_base58");
	let bytes = [];
	for (const ch of text) {
		let carry = BASE58.indexOf(ch);
		if (carry < 0) throw new Error("invalid_base58");
		for (let i = 0; i < bytes.length; i += 1) {
			carry += bytes[i] * 58;
			bytes[i] = carry & 0xff;
			carry >>= 8;
		}
		while (carry > 0) {
			bytes.push(carry & 0xff);
			carry >>= 8;
		}
	}
	for (let i = 0; i < text.length && text[i] === "1"; i += 1) bytes.push(0);
	return Uint8Array.from(bytes.reverse());
}

function base58Encode(bytes) {
	const digits = [];
	for (const byte of bytes) {
		let carry = byte;
		for (let i = 0; i < digits.length; i += 1) {
			carry += digits[i] << 8;
			digits[i] = carry % 58;
			carry = (carry / 58) | 0;
		}
		while (carry > 0) {
			digits.push(carry % 58);
			carry = (carry / 58) | 0;
		}
	}
	let out = "";
	for (let i = 0; i < bytes.length && bytes[i] === 0; i += 1) out += "1";
	for (let i = digits.length - 1; i >= 0; i -= 1) out += BASE58[digits[i]];
	return out;
}

/** Returns "" when the link is valid, otherwise a short error code. */
function verifyWalletLink({ uid, address, message, signature, nowMs = Date.now() }) {
	if (!uid) return "no_uid";
	if (typeof message !== "string" || message.length === 0 || message.length > MAX_MESSAGE) return "bad_message";
	let pubkey;
	let sig;
	try {
		pubkey = base58Decode(String(address || ""));
		sig = base58Decode(String(signature || ""));
	} catch (error) {
		return "bad_encoding";
	}
	if (pubkey.length !== 32) return "bad_address";
	if (sig.length !== 64) return "bad_signature";
	const firstLine = message.split("\n")[0] || "";
	const domain = firstLine.split(" wants you to sign in with your Solana account:")[0];
	if (!firstLine.includes(" wants you to sign in with your Solana account:") || !ALLOWED_DOMAINS.includes(domain)) {
		return "bad_domain";
	}
	if (!message.includes(address)) return "address_mismatch";
	if (!message.includes(`nocaps:player:${uid}`)) return "player_mismatch";
	const issued = /Issued At: (\S+)/.exec(message);
	const issuedMs = issued ? Date.parse(issued[1]) : NaN;
	if (!Number.isFinite(issuedMs) || Math.abs(nowMs - issuedMs) > ISSUED_AT_WINDOW_MS) return "stale_message";
	const ok = nacl.sign.detached.verify(new TextEncoder().encode(message), sig, pubkey);
	return ok ? "" : "bad_signature";
}

module.exports = { verifyWalletLink, base58Decode, base58Encode, playerNameOk, ISSUED_AT_WINDOW_MS };
