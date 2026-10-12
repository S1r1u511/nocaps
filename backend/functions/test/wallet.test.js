// node test/wallet.test.js  (needs `npm install` in backend/functions)
const assert = require("node:assert");
const nacl = require("tweetnacl");
const { verifyWalletLink, base58Decode, base58Encode, playerNameOk } = require("../wallet");

const kp = nacl.sign.keyPair();
const address = base58Encode(kp.publicKey);
const uid = "AbCdEf123456";
const now = Date.parse("2026-10-10T12:00:00Z");
const siws = (o = {}) => `${o.domain || "nocaps.fun"} wants you to sign in with your Solana account:\n${o.address || address}\n\nSign in to NOCAPS to verify this wallet is yours. Player: nocaps:player:${o.uid || uid}\n\nURI: https://nocaps.fun\nVersion: 1\nNonce: abc123\nIssued At: ${o.issued || "2026-10-10T11:58:00Z"}`;
const sign = (text, key = kp.secretKey) => base58Encode(nacl.sign.detached(new TextEncoder().encode(text), key));

let n = 0;
const t = (label, fn) => { fn(); n += 1; console.log("PASS ", label); };
t("base58 round trip", () => { const b = Uint8Array.from([0, 0, 1, 2, 255]); assert.deepStrictEqual(base58Decode(base58Encode(b)), b); });
t("base58 of a 32-byte key decodes to 32 bytes", () => assert.strictEqual(base58Decode(address).length, 32));
t("valid link", () => { const m = siws(); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: sign(m), nowMs: now }), ""); });
t("tampered message rejected", () => { const m = siws(); assert.strictEqual(verifyWalletLink({ uid, address, message: m + " ", signature: sign(m), nowMs: now }), "bad_signature"); });
t("other key's signature rejected", () => { const m = siws(); const other = nacl.sign.keyPair(); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: sign(m, other.secretKey), nowMs: now }), "bad_signature"); });
t("other player's message rejected", () => { const m = siws({ uid: "someoneElse" }); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: sign(m), nowMs: now }), "player_mismatch"); });
t("other address in message rejected", () => { const o = base58Encode(nacl.sign.keyPair().publicKey); const m = siws({ address: o }); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: sign(m), nowMs: now }), "address_mismatch"); });
t("wrong domain rejected", () => { const m = siws({ domain: "evil.example" }); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: sign(m), nowMs: now }), "bad_domain"); });
t("stale message rejected", () => { const m = siws({ issued: "2026-10-10T10:00:00Z" }); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: sign(m), nowMs: now }), "stale_message"); });
t("garbage signature rejected", () => { const m = siws(); assert.strictEqual(verifyWalletLink({ uid, address, message: m, signature: "0OIl", nowMs: now }), "bad_encoding"); });
t("names mirror the app", () => { assert(playerNameOk("Guest 1234")); assert(playerNameOk("Divy_11")); assert(!playerNameOk("guestking")); assert(!playerNameOk("bad name")); assert(!playerNameOk("shitlord")); });
console.log(`\n${n} passed`);
