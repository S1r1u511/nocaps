# NOCAPS backend — Firebase (Cloud Functions + Firestore)

Client-agnostic HTTPS API for the Godot client. The game is fully playable offline; runs are queued
locally and submitted when the backend is reachable. **Emulator-verified 2026-09-25; not deployed to a
real Firebase project yet** — see `docs/10_BACKEND.md` §14 and the verification steps below.

Canonical reference: `docs/10_BACKEND.md`.

## Layout

```text
backend/
├── firebase.json              # functions + firestore + emulator config
├── firestore.rules            # public leaderboard reads; functions-only writes
├── firestore.indexes.json     # period-close index
├── .firebaserc.example        # copy to .firebaserc and set your project id
└── functions/
    ├── package.json
    └── index.js               # all endpoints + scheduled rollover
```

## API surface

| Endpoint | Method | Purpose |
|---|---|---|
| `submitRun` | POST | Validate + record a run; update daily/weekly aggregates |
| `getLeaderboard` | GET/POST | `view=communities\|players`, `period=daily\|weekly` |
| `getPlayerProfile` | GET/POST | Read the caller's player document |
| `requestWalletChallenge` | POST | Issue a nonce/message for wallet linking |
| `verifyWalletSignature` | POST | Verify an Ed25519 signature and bind the wallet |
| `rolloverPeriods` | scheduled | Open/close UTC daily + weekly period documents |

Every request must carry a Firebase ID token: `Authorization: Bearer <idToken>`. The server derives
`uid` from the token, never from the body. Request payloads use camelCase (`runId`, `communityId`,
`durationMs`, …); the Godot client maps its local snake_case record in `platform/backend_client.gd`.

Trust model for the demo: plausibility checks, a minimum submit interval, idempotent `runId`, and
server-recomputed contribution/streak. `rewardEligible` is always `false`. See `docs/10_BACKEND.md` §8.

## Local emulator (no real project needed)

```bash
cd backend
npm install --prefix functions
cp .firebaserc.example .firebaserc      # set "default": "demo-nocaps" (any demo- id works)
npx firebase-tools emulators:start --only auth,functions,firestore,pubsub --project demo-nocaps
```

The Functions emulator serves `http://127.0.0.1:5001/demo-nocaps/us-central1`; Auth is on `:9099`,
Firestore on `:8080`, Pub/Sub on `:8085`. The Godot client auto-configures these URLs when run from the
editor, and `BackendClient.configure_for_emulator()` sets them explicitly.

Verify the running emulator (25 checks: auth, submission, idempotency, rate limit, aggregates, rules,
wallet signature, rollover):

```bash
backend/scripts/verify_emulator.sh
scripts/run_tests.sh --emulator
```

## Setup (one-time, real project owner)

1. Install the CLI: `npm install -g firebase-tools` (or `npx firebase-tools`).
2. Create a Firebase project in the console (or `firebase projects:create`).
3. Enable **Authentication → Anonymous** sign-in.
4. Create a **Firestore** database (production mode).
5. In `backend/`: `cp .firebaserc.example .firebaserc` and set your project id.
6. `cd functions && npm install`.
7. Deploy: `firebase deploy --only functions,firestore` (from `backend/`).

## Client configuration

The client needs (all non-secret):

- functions base URL;
- Auth base URL + web API key (the emulator uses `fake-api-key`).

`platform/backend_client.gd` signs in anonymously, refreshes the ID token, and maps the local run
record to the camelCase payload. It auto-configures the local emulator when running from the editor;
`configure()` points it at a real project. No secret keys ship in the app.

## Verification status

- **Emulator-verified 2026-09-25** against `demo-nocaps`; results in `docs/10_BACKEND.md` §14.
- `backend/scripts/verify_emulator.sh`: 25/25 checks passing (auth guards, submission validation,
  idempotency, rate limit, daily/weekly aggregates, rules, wallet signature, rollover).
- `tests/backend_emulator_smoke.gd`: the Godot client signs in, submits, and reads live rows.
- **Production `nocaps-v1`:** project created, Anonymous Auth enabled, Firestore `(default)` in `nam5`
  with rules + indexes deployed, client config in `project.godot`. **Cloud Functions deploy is pending
  the Blaze upgrade.**
- After Blaze: `npx firebase-tools deploy --only functions --project nocaps-v1`, then
  `backend/scripts/verify_production.sh` (it preflights the deployment and cleans up its test data).
