// Firestore rules tests for build 1.0.0 (Oct 10): per-run cap, player names,
// admin-only champions, server-owned periods (offline rule C).
//
// Run from backend/tests:  npm install && npm test
// (starts the Firestore emulator for project demo-nocaps and runs this file)

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc, writeBatch, serverTimestamp, increment, Timestamp, setDoc,
} from "firebase/firestore";

const here = dirname(fileURLToPath(import.meta.url));
const env = await initializeTestEnvironment({
  projectId: "demo-nocaps",
  firestore: { rules: readFileSync(join(here, "..", "firestore.rules"), "utf8") },
});

const DAY = 86400000;
const pad = (n) => String(n).padStart(2, "0");
const ymd = (ms) => { const d = new Date(ms); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`; };
const dayStart = (ms) => Math.floor(ms / DAY) * DAY;
const weekStart = (ms) => { const s = dayStart(ms); const wd = (new Date(s).getUTCDay() + 6) % 7; return s - wd * DAY; };
function isoWeek(ms) {
  const d = new Date(dayStart(ms));
  const day = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - day + 3);
  const firstThu = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(((d - firstThu) / DAY - 3 + ((firstThu.getUTCDay() + 6) % 7)) / 7);
  return `${d.getUTCFullYear()}-W${pad(week)}`;
}

const now = Date.now();
const today = { key: `daily_${ymd(now)}`, start: Timestamp.fromMillis(dayStart(now)) };
const yesterday = { key: `daily_${ymd(now - DAY)}`, start: Timestamp.fromMillis(dayStart(now - DAY)) };
const week = { key: `weekly_${isoWeek(now)}`, start: Timestamp.fromMillis(weekStart(now)) };
const lastWeek = { key: `weekly_${isoWeek(now - 7 * DAY)}`, start: Timestamp.fromMillis(weekStart(now - 7 * DAY)) };

let n = 0;
// One commit as the app sends it (platform/backend_client.gd _submit).
async function runCommit({ score = 100, name = "Guest 1234", day = today, wk = week, entries = true, uid } = {}) {
  uid = uid || `u${++n}`;
  const db = env.authenticatedContext(uid).firestore();
  const runId = `${uid}-run-${n}`;
  const crew = "mole";
  const b = writeBatch(db);
  b.set(doc(db, "rate_limits", uid), { lastSubmitAt: serverTimestamp() });
  b.set(doc(db, "runs", runId), {
    uid, communityId: crew, score, contribution: score, landings: Math.min(10, score),
    duration: 120000, createdAt: serverTimestamp(),
  });
  if (entries) {
    for (const p of [day, wk]) {
      b.set(doc(db, `leaderboards/${p.key}/entries`, `community_${crew}`), {
        entityType: "community", communityId: crew, name: "Mole", periodKey: p.key,
        periodStart: p.start, source: "run", lastRunId: runId,
        score: increment(score), landings: increment(Math.min(10, score)),
      }, { merge: true });
      b.set(doc(db, `leaderboards/${p.key}/entries`, `player_${uid}_${crew}`), {
        entityType: "player", communityId: crew, name, uid, periodKey: p.key,
        periodStart: p.start, source: "run", lastRunId: runId,
        score: increment(score), runs: increment(1),
      }, { merge: true });
    }
  }
  return b.commit();
}

const results = [];
async function check(label, fn) {
  try { await fn(); results.push(["PASS", label]); }
  catch (e) { results.push(["FAIL", label, e.message.split("\n")[0]]); }
}

// --- A1: per-run cap, names, champions -------------------------------------
await check("valid run (score 100, guest name) is accepted", () => assertSucceeds(runCommit()));
await check("run of 1000 is accepted", () => assertSucceeds(runCommit({ score: 1000 })));
await check("run of 1001 is rejected", () => assertFails(runCommit({ score: 1001 })));
await check("chosen name Divy_11 is accepted", () => assertSucceeds(runCommit({ name: "Divy_11" })));
await check("name with spaces/symbols is rejected", () => assertFails(runCommit({ name: "bad name!" })));
await check("blocklisted name is rejected", () => assertFails(runCommit({ name: "shitlord" })));
await check("name starting with guest (not the guest pattern) is rejected", () => assertFails(runCommit({ name: "guestking" })));
await check("17-char name is rejected", () => assertFails(runCommit({ name: "a".repeat(17) })));
await check("client cannot create a champion", () => assertFails(
  setDoc(doc(env.authenticatedContext("champ").firestore(), "champions", `${today.key}_mole`), {
    periodKey: today.key, periodStart: today.start, communityId: "mole", winner: "Mole",
    score: 10, mvpUid: "x", createdAt: serverTimestamp(),
  })));

// --- A2: server-owned periods + offline rule C -----------------------------
await check("today's day + this week is accepted", () => assertSucceeds(runCommit({ day: today, wk: week })));
await check("yesterday's daily entry is rejected", () => assertFails(runCommit({ day: yesterday })));
await check("daily key not matching its start date is rejected", () => assertFails(
  runCommit({ day: { key: yesterday.key, start: today.start } })));
await check("last week's weekly entry is rejected", () => assertFails(runCommit({ wk: lastWeek })));
await check("run-only commit (personal score, rule C) is accepted", () => assertSucceeds(runCommit({ entries: false })));

// --- A3: config/app -------------------------------------------------------
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), "config", "app"), { minVersion: "1.0.0", latestVersion: "1.0.0", message: "", updateUrl: "" });
});
const { getDoc } = await import("firebase/firestore");
await check("anyone can read config/app", () => assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "config", "app"))));
await check("clients cannot write config/app", () => assertFails(
  setDoc(doc(env.authenticatedContext("cfg").firestore(), "config", "app"), { minVersion: "0.0.1" })));

// --- A4: wallet links are server-written only -------------------------------
await check("client cannot write its own wallet link", () => assertFails(
  setDoc(doc(env.authenticatedContext("w1").firestore(), "wallet_links", "w1"), {
    uid: "w1", wallet: "11111111111111111111111111111111", message: "x",
    signature: "1".repeat(64), method: "wallet", name: "Guest 1234", linkedAt: serverTimestamp(),
  })));
await check("anyone can read wallet links", () => assertSucceeds(
  getDoc(doc(env.unauthenticatedContext().firestore(), "wallet_links", "w1"))));

await env.cleanup();
for (const r of results) console.log(r.join("  "));
const failed = results.filter((r) => r[0] === "FAIL").length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
