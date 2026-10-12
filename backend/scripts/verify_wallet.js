#!/usr/bin/env node
/**
 * Wallet-link verification helper for the NOCAPS emulator run.
 *
 * Signs the server-issued challenge with a fresh Ed25519 keypair and checks the
 * full path: valid signature links the wallet, a challenge cannot be reused, and
 * a signature from the wrong key is rejected. Uses the tweetnacl copy already
 * installed for the Cloud Functions.
 *
 * Usage: node verify_wallet.js <functionsBaseUrl> <idToken>
 */

const path = require("path");
const nacl = require(path.join(__dirname, "..", "functions", "node_modules", "tweetnacl"));

const BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

function base58Encode(bytes) {
	let value = 0n;
	for (const byte of bytes) {
		value = (value << 8n) + BigInt(byte);
	}
	let text = "";
	while (value > 0n) {
		text = BASE58[Number(value % 58n)] + text;
		value /= 58n;
	}
	for (const byte of bytes) {
		if (byte !== 0) {
			break;
		}
		text = "1" + text;
	}
	return text;
}

async function call(url, token, body) {
	const response = await fetch(url, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Authorization: `Bearer ${token}`,
		},
		body: JSON.stringify(body),
	});
	return { status: response.status, body: await response.json() };
}

async function main() {
	const [base, token] = process.argv.slice(2);
	if (!base || !token) {
		console.error("usage: node verify_wallet.js <functionsBaseUrl> <idToken>");
		process.exit(2);
	}

	const results = [];
	const check = (name, passed, detail) => results.push({ name, passed, detail });

	const challenge = await call(`${base}/requestWalletChallenge`, token, {});
	check(
		"requestWalletChallenge issues a message",
		challenge.status === 200 && Boolean(challenge.body.message),
		JSON.stringify(challenge.body)
	);

	const good = nacl.sign.keyPair();
	const goodPubkey = base58Encode(good.publicKey);
	const signature = Buffer.from(
		nacl.sign.detached(Buffer.from(challenge.body.message, "utf8"), good.secretKey)
	).toString("base64");

	const verified = await call(`${base}/verifyWalletSignature`, token, {
		walletPubkey: goodPubkey,
		signature,
	});
	check(
		"valid Ed25519 signature links the wallet",
		verified.status === 200 && verified.body.ok === true,
		JSON.stringify(verified.body)
	);

	const replay = await call(`${base}/verifyWalletSignature`, token, {
		walletPubkey: goodPubkey,
		signature,
	});
	check(
		"challenge cannot be reused",
		replay.status === 400 && replay.body.error === "challenge_used",
		JSON.stringify(replay.body)
	);

	const second = await call(`${base}/requestWalletChallenge`, token, {});
	const wrong = nacl.sign.keyPair();
	const wrongSignature = Buffer.from(
		nacl.sign.detached(Buffer.from(second.body.message, "utf8"), wrong.secretKey)
	).toString("base64");
	const rejected = await call(`${base}/verifyWalletSignature`, token, {
		walletPubkey: goodPubkey,
		signature: wrongSignature,
	});
	check(
		"wrong-key signature is rejected",
		rejected.status === 400 && rejected.body.error === "bad_signature",
		JSON.stringify(rejected.body)
	);

	const profile = await call(`${base}/getPlayerProfile`, token, {});
	check(
		"wallet address is recorded on the player",
		Boolean(profile.body.player) && profile.body.player.walletAddress === goodPubkey,
		JSON.stringify(profile.body.player || {})
	);

	let failed = 0;
	for (const result of results) {
		console.log(`${result.passed ? "PASS" : "FAIL"}  ${result.name}${result.passed ? "" : "  " + result.detail}`);
		if (!result.passed) {
			failed += 1;
		}
	}
	process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
	console.error(error);
	process.exit(2);
});
