package com.nocapsfun.bridge

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.view.View
import androidx.activity.ComponentActivity
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.Blockchain
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.RpcCluster
import com.solana.mobilewalletadapter.clientlib.Solana
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.mobilewalletadapter.common.signin.SignInWithSolana
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot-facing Solana Mobile Wallet Adapter boundary.
 *
 * ## Wallet policy (hard rules — see docs/13_WALLET_MWA_PLAN.md §0)
 *
 * This plugin is the ONLY place in the app that talks to a wallet, and it is
 * limited to:
 *   1. Sign-In-With-Solana (authorize + sign a human-readable message in one
 *      approval);
 *   2. off-chain message signing of caller-provided UTF-8 text
 *      (`signMessagesDetached`) as a challenge/response fallback;
 *   3. deauthorize (disconnect);
 *   4. session persistence of the public address + MWA auth token.
 *
 * It MUST NOT and does NOT: sign or send transactions, transfer tokens/NFTs,
 * request token approvals or delegations, batch/"sign all" requests, blind-sign
 * opaque bytes, auto-sign without a user tap, run background/hidden wallet
 * requests, or do anything that could move or lock user funds. No seed phrase or
 * private key is ever requested, stored, logged, or transmitted, and the full
 * auth token is never logged. Every request here starts because the app's UI
 * called a `@UsedByGodot` method following an explicit user tap.
 *
 * Godot never sees MWA types: it calls [connect_wallet] (sign-in),
 * [disconnect_wallet], and [sign_message], and listens for the wallet_* signals.
 * Every failure path emits `wallet_error` with a stable code (no_wallet,
 * cancelled, timeout, unavailable, not_connected, auth, unknown) instead of
 * throwing.
 *
 * The active cluster is NOT hard-coded: Godot passes the `nocaps/wallet/cluster`
 * project setting through [connect_wallet] and [sign_message] reuses the token
 * from that same authorize session. "devnet" and "mainnet-beta" are the only
 * values used today; switching is a one-line project setting change.
 *
 * MWA requires an `ActivityResultSender` bound to a `ComponentActivity` before
 * that activity reaches STARTED; Godot 4.7's `GodotActivity` is a
 * `FragmentActivity`, so [onMainCreate] is the only safe place to register it.
 */
class NocapsWalletPlugin(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "NocapsWallet"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("wallet_connected", String::class.java),
        SignalInfo("wallet_disconnected"),
        SignalInfo("wallet_error", String::class.java, String::class.java),
        SignalInfo("wallet_signed", String::class.java, String::class.java),
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var sender: ActivityResultSender? = null
    private var adapter: MobileWalletAdapter? = null

    /** Base58 public address of the authorized account, empty when disconnected. */
    private var address: String = ""

    /** MWA session token. Never logged, never leaves the device. */
    private var authToken: String? = null

    /** Cluster requested by Godot as a project setting; devnet until told otherwise. */
    private var clusterName: String = DEFAULT_CLUSTER
    private var busy: Boolean = false

    override fun onMainCreate(activity: Activity?): View? {
        if (sender == null && activity is ComponentActivity) {
            sender = ActivityResultSender(activity)
            restoreSession()
        }
        return super.onMainCreate(activity)
    }

    override fun onMainDestroy() {
        scope.cancel()
        super.onMainDestroy()
    }

    @UsedByGodot
    fun is_wallet_available(): Boolean = sender != null

    @UsedByGodot
    fun get_wallet_address(): String = address

    @UsedByGodot
    fun get_cluster(): String = clusterName

    /**
     * One-tap Sign-In-With-Solana: authorize + sign a human-readable sign-in
     * message in a single wallet approval. Godot supplies the [domain], the
     * [statement] the user will read, and the [nonce]/[issuedAt]/[requestId] it
     * generated; this never signs anything the user was not shown. Returns the
     * public key via `wallet_connected` and the signed message + base58 signature
     * via `wallet_signed`.
     */
    @UsedByGodot
    fun connect_wallet(domain: String, statement: String, nonce: String, issuedAt: String, cluster: String, requestId: String) {
        if (busy) return
        val resultSender = sender ?: return fail("unavailable", "Wallet bridge not ready")
        busy = true
        clusterName = cluster.ifBlank { DEFAULT_CLUSTER }
        scope.launch {
            try {
                val client = newAdapter()
                val payload = SignInWithSolana.Payload(
                    domain,
                    null as String?,
                    statement,
                    Uri.parse(APP_URI),
                    SIGN_IN_VERSION,
                    client.blockchain.fullName,
                    nonce,
                    issuedAt,
                    null,
                    null,
                    requestId.ifBlank { null },
                    emptyArray<Uri>(),
                )
                when (val result = client.signIn(resultSender, payload)) {
                    is TransactionResult.Success -> {
                        val signIn = result.payload
                        address = base58Encode(signIn.publicKey)
                        authToken = client.authToken
                        adapter = client
                        persist()
                        val message = String(signIn.signedMessage, Charsets.UTF_8)
                        val signature = base58Encode(signIn.signature)
                        Log.i(TAG, "sign-in ok: $address")
                        Log.i(TAG, "sign-in signature: $signature")
                        emitSignal("wallet_connected", address)
                        emitSignal("wallet_signed", message, signature)
                    }
                    is TransactionResult.NoWalletFound -> {
                        Log.w(TAG, "no wallet installed")
                        fail("no_wallet", result.message)
                    }
                    is TransactionResult.Failure -> {
                        Log.w(TAG, "sign-in failed: ${result.message}")
                        fail(mapFailure(result.message), result.message)
                    }
                }
            } catch (t: Throwable) {
                fail("unknown", t.message ?: t.javaClass.simpleName)
            } finally {
                busy = false
            }
        }
    }

    /** Deauthorizes the wallet (invalidates the auth token) and wipes local state. */
    @UsedByGodot
    fun disconnect_wallet() {
        val resultSender = sender
        val client = adapter
        if (resultSender == null || client == null) {
            clearSession()
            emitSignal("wallet_disconnected")
            return
        }
        scope.launch {
            try {
                when (val result = client.disconnect(resultSender)) {
                    is TransactionResult.Success -> Log.i(TAG, "deauthorize ok")
                    is TransactionResult.NoWalletFound -> Log.w(TAG, "deauthorize: no wallet")
                    is TransactionResult.Failure -> Log.w(TAG, "deauthorize failed: ${result.message}")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "deauthorize threw: ${t.message}")
            } finally {
                // Always wipe locally: a failed deauthorize must not leave a stale
                // token or address on the device.
                clearSession()
                adapter = null
                emitSignal("wallet_disconnected")
            }
        }
    }

    /**
     * Signs caller-provided UTF-8 text (a backend challenge) with the authorized
     * account and returns the detached Ed25519 signature (base58) via
     * `wallet_signed`. Reuses the token from the sign-in authorize session, so it
     * is a silent reauthorize (no separate user-facing authorize step). It never
     * signs anything the caller did not pass and never touches transactions.
     */
    @UsedByGodot
    fun sign_message(message: String) {
        val resultSender = sender ?: return fail("unavailable", "Wallet bridge not ready")
        val client = adapter ?: authToken?.let { newAdapter().also { adapter = it } }
            ?: return fail("not_connected", "Connect a wallet first")
        scope.launch {
            try {
                val result = client.transact(resultSender) { authResult ->
                    val key = authResult.accounts.firstOrNull()?.publicKey ?: authResult.publicKey
                        ?: throw IllegalStateException("Wallet returned no account")
                    signMessagesDetached(
                        arrayOf(message.toByteArray(Charsets.UTF_8)),
                        arrayOf(key),
                    )
                }
                when (result) {
                    is TransactionResult.Success -> {
                        val signature = result.payload.messages.firstOrNull()?.signatures?.firstOrNull()
                        if (signature == null) {
                            fail("unknown", "Wallet returned no signature")
                        } else {
                            emitSignal("wallet_signed", message, base58Encode(signature))
                        }
                    }
                    is TransactionResult.NoWalletFound -> fail("no_wallet", result.message)
                    is TransactionResult.Failure -> fail(mapFailure(result.message), result.message)
                }
            } catch (t: Throwable) {
                fail("unknown", t.message ?: t.javaClass.simpleName)
            }
        }
    }

    // --- session persistence (public address + auth token only) --------------

    private fun prefs(): SharedPreferences =
        getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun restoreSession() {
        val stored = prefs().getString(KEY_ADDRESS, "").orEmpty()
        if (stored.isNotEmpty()) {
            address = stored
            authToken = prefs().getString(KEY_AUTH_TOKEN, null)
        }
    }

    private fun persist() {
        prefs().edit()
            .putString(KEY_ADDRESS, address)
            .putString(KEY_AUTH_TOKEN, authToken)
            .apply()
    }

    private fun clearSession() {
        address = ""
        authToken = null
        prefs().edit().clear().apply()
    }

    // --- identity + cluster ---------------------------------------------------

    /**
     * The app identity wallets show during approval. MWA requires [APP_ICON] to
     * be a **relative** path; it is resolved against [APP_URI], so the effective
     * icon is the hosted absolute URL https://nocaps.fun/wallet-icon.png.
     */
    private fun connectionIdentity(): ConnectionIdentity = ConnectionIdentity(
        identityUri = Uri.parse(APP_URI),
        iconUri = Uri.parse(APP_ICON),
        identityName = APP_NAME,
    )

    /**
     * Maps the Godot `nocaps/wallet/cluster` setting to an MWA blockchain/RPC
     * pair. This is the single place cluster names are interpreted; the selected
     * value always comes from the project setting, never a literal in call sites.
     */
    private fun clusterFor(name: String): Pair<Blockchain, RpcCluster> =
        when (name.trim().lowercase()) {
            "mainnet", "mainnet-beta", "mainnetbeta" -> Solana.Mainnet to RpcCluster.MainnetBeta
            "testnet" -> Solana.Testnet to RpcCluster.Testnet
            "devnet" -> Solana.Devnet to RpcCluster.Devnet
            else -> {
                Log.w(TAG, "unknown cluster '$name'; falling back to devnet")
                Solana.Devnet to RpcCluster.Devnet
            }
        }

    private fun newAdapter(): MobileWalletAdapter {
        val client = MobileWalletAdapter(connectionIdentity = connectionIdentity())
        val (chain, cluster) = clusterFor(clusterName)
        client.blockchain = chain
        client.rpcCluster = cluster
        authToken?.let { client.authToken = it }
        return client
    }

    // --- error + encoding helpers --------------------------------------------

    private fun fail(code: String, detail: String) {
        Log.w(TAG, "wallet_error [$code]: $detail")
        emitSignal("wallet_error", code, detail)
    }

    private fun mapFailure(message: String?): String {
        val text = message.orEmpty().lowercase()
        return when {
            text.contains("timed out") || text.contains("timeout") -> "timeout"
            text.contains("interrupt") || text.contains("cancel") -> "cancelled"
            text.contains("auth token") || text.contains("authorization") -> "auth"
            else -> "unknown"
        }
    }

    private fun base58Encode(input: ByteArray): String {
        if (input.isEmpty()) return ""
        var zeros = 0
        while (zeros < input.size && input[zeros].toInt() == 0) zeros++
        val digits = ArrayList<Int>()
        for (byte in input) {
            var carry = byte.toInt() and 0xFF
            for (i in digits.indices) {
                carry += digits[i] shl 8
                digits[i] = carry % 58
                carry /= 58
            }
            while (carry > 0) {
                digits.add(carry % 58)
                carry /= 58
            }
        }
        val out = StringBuilder()
        repeat(zeros) { out.append(BASE58_ALPHABET[0]) }
        for (i in digits.indices.reversed()) out.append(BASE58_ALPHABET[digits[i]])
        return out.toString()
    }

    private companion object {
        const val TAG = "NocapsWallet"
        const val PREFS = "nocaps_wallet"
        const val KEY_ADDRESS = "wallet_address"
        const val KEY_AUTH_TOKEN = "wallet_auth_token"

        // App identity wallets show during approval. The icon is a RELATIVE path
        // resolved against APP_URI, so it must be hosted at
        // https://nocaps.fun/wallet-icon.png; see docs/13_WALLET_MWA_PLAN.md §3.
        const val APP_NAME = "NOCAPS"
        const val APP_URI = "https://nocaps.fun"
        const val APP_ICON = "wallet-icon.png"

        // Cluster fallback when Godot does not send one; the project setting
        // `nocaps/wallet/cluster` is the source of truth.
        const val DEFAULT_CLUSTER = "devnet"
        const val SIGN_IN_VERSION = "1"
        const val BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    }
}
