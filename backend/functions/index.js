/**
 * NOCAPS Cloud Functions (deployed on Blaze). Only what the database rules
 * cannot do runs here (Oct 10): verifying wallet signatures.
 *
 * The pre-Spark functions (submitRun, getLeaderboard, ...) live in
 * legacy/index_v0.js and are NOT exported or deployed: runs are written by the
 * app under backend/firestore.rules.
 */
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { onRequest } = require("firebase-functions/v2/https");
const { verifyWalletLink, playerNameOk } = require("./wallet");

initializeApp();
const db = getFirestore();

/**
 * POST /linkWallet   Authorization: Bearer <Firebase ID token>
 * body: { address, message (SIWS text) | messageB64, signature (base58), method, name }
 * -> 200 { ok: true, verified: true, wallet } | 4xx { ok: false, error }
 * Writes wallet_links/{uid} (clients can no longer write it directly).
 */
// invoker "public": the app calls this without Google IAM credentials; the
// function itself checks the Firebase ID token. Without it, Cloud Run answers
// 403 (HTML) before our code runs.
exports.linkWallet = onRequest({ region: "us-central1", cors: true, maxInstances: 5, invoker: "public" }, async (req, res) => {
	if (req.method !== "POST") {
		return res.status(405).json({ ok: false, error: "method_not_allowed" });
	}
	const header = String(req.get("authorization") || "");
	if (!header.startsWith("Bearer ")) {
		return res.status(401).json({ ok: false, error: "missing_token" });
	}
	let uid;
	try {
		uid = (await getAuth().verifyIdToken(header.slice(7))).uid;
	} catch (error) {
		return res.status(401).json({ ok: false, error: "invalid_token" });
	}
	const body = req.body || {};
	const address = String(body.address || "");
	const message = body.messageB64
		? Buffer.from(String(body.messageB64), "base64").toString("utf8")
		: String(body.message || "");
	const signature = String(body.signature || "");
	const method = ["wallet", "privy"].includes(body.method) ? body.method : "wallet";
	const name = String(body.name || "");
	if (!playerNameOk(name)) {
		console.warn("linkWallet rejected", { uid, error: "bad_name", name });
		return res.status(400).json({ ok: false, error: "bad_name" });
	}
	const problem = verifyWalletLink({ uid, address, message, signature });
	if (problem) {
		// The first line + Issued At help debug wallet formatting; no secrets here.
		console.warn("linkWallet rejected", { uid, error: problem, firstLine: message.split("\n")[0], issuedAt: (/Issued At: (\S+)/.exec(message) || [])[1] || null });
		return res.status(400).json({ ok: false, error: problem });
	}
	console.log("linkWallet ok", { uid, wallet: address });
	await db.doc(`wallet_links/${uid}`).set({
		uid,
		wallet: address,
		message: Buffer.from(message, "utf8").toString("base64"),
		signature,
		method,
		name,
		verified: true,
		linkedAt: FieldValue.serverTimestamp(),
	});
	return res.status(200).json({ ok: true, verified: true, wallet: address });
});
