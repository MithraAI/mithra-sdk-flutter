package com.mithra.flutter.sdk

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.mithra.sdk.kotlin.android.Analytics
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import java.io.File

/**
 * Process-wide owner of the native [Analytics] instance.
 *
 * A Flutter app can run several engines in one process: the main engine, and
 * the one `firebase_messaging` spins up for `onBackgroundMessage` while the app
 * is backgrounded or terminated. Each engine gets its own
 * [MithraFlutterSdkPlugin] instance, but the Narya SDK must exist exactly once
 * per process, so the instance lives here rather than on the plugin.
 *
 * The holder also persists the last successfully applied `NaryaConfiguration`
 * wire map. In a fresh process the background engine's plugin never sees a
 * `initialize` call (Dart's `Narya.initialize` runs in the main isolate only),
 * yet `push.handlePushMessage` must still render the notification. [obtain]
 * therefore rebuilds the instance from the persisted map, through the same
 * [NaryaConfigurationCodec] the live call uses, so both paths produce an
 * identical SDK configuration.
 *
 * The write key is split out of that persisted map and kept in
 * `EncryptedSharedPreferences` instead, matching the native SDK's own
 * `EncryptedKeyValueStore`: plaintext app preferences are readable on a rooted
 * device, by any process sharing the app's UID, and end up in `adb backup` and
 * in auto backup, which is on by default. Everything else in the map is
 * behaviour, not a secret, so only the key needs the keystore. When the
 * keystore is unavailable the write key is simply not persisted and a
 * background engine reports `not_initialized` rather than the SDK writing a
 * credential to disk in the clear.
 */
internal object NaryaAnalyticsHolder {

    private const val TAG = "MithraFlutterSdk"
    private const val PREFERENCES = "com.mithra.flutter.sdk"
    private const val PREFERENCES_SECURE = "com.mithra.flutter.sdk.secure"
    private const val KEY_CONFIGURATION = "configuration"
    private const val KEY_WRITE_KEY = "writeKey"

    /** Opened on first use; `null` once opening it has failed in this process. */
    @Volatile
    private var securePreferences: SharedPreferences? = null

    @Volatile
    private var securePreferencesResolved = false

    @Volatile
    private var instance: Analytics? = null

    @Volatile
    private var identity: String? = null

    /** The live instance, or `null` when nothing has been initialized or restored yet. */
    val analytics: Analytics?
        get() = instance

    /** The [NaryaConfigurationCodec.identityOf] key of the live instance's configuration. */
    val configurationIdentity: String?
        get() = identity

    /**
     * Constructs the instance from a Dart configuration map and persists the map.
     *
     * The caller checked that no instance exists, but that check is outside
     * this lock: two engines - the main one and a `firebase_messaging`
     * background engine - can reach it at the same time. This re-check is the
     * authority. An instance built from the same configuration is handed back,
     * which is the idempotent hot-restart case; one built from a *different*
     * configuration raises `already_initialized`, because silently handing the
     * loser the first instance would tell an engine that its own write key had
     * been applied when it had not.
     *
     * Throws [NaryaConfigurationException] when the map cannot produce a
     * configuration; nothing is persisted in that case.
     */
    @Synchronized
    fun create(application: Application, source: Map<*, *>?): Analytics {
        instance?.let { existing ->
            if (NaryaConfigurationCodec.identityOf(source) == identity) return existing
            throw NaryaConfigurationException(
                "already_initialized",
                "Narya was initialized concurrently with a different configuration. " +
                    "Call Narya.shutdown() before initializing again.",
            )
        }
        val configuration = NaryaConfigurationCodec.decode(application, source)
        val created = Analytics(configuration)
        instance = created
        identity = NaryaConfigurationCodec.identityOf(source)
        persist(application, source)
        return created
    }

    /**
     * Returns the live instance, restoring it from the persisted configuration
     * when this process has not initialized the SDK yet.
     *
     * Returns `null` when there is no live instance and no persisted
     * configuration (the app never completed `Narya.initialize` on this device,
     * or `Narya.shutdown` cleared it), or when the persisted map no longer
     * decodes. Restoration is logged at debug level.
     */
    @Synchronized
    fun obtain(context: Context): Analytics? {
        instance?.let { return it }
        val application = context.applicationContext as? Application ?: return null
        val source = readPersisted(application) ?: return null
        return try {
            val restored = Analytics(NaryaConfigurationCodec.decode(application, source))
            instance = restored
            identity = NaryaConfigurationCodec.identityOf(source)
            Log.d(
                TAG,
                "Narya restored from the persisted configuration; " +
                    "Narya.initialize has not run in this process (background engine)",
            )
            restored
        } catch (error: NaryaConfigurationException) {
            Log.w(TAG, "Persisted Narya configuration is unusable: ${error.message}")
            null
        }
    }

    /**
     * Forgets the live instance and the persisted configuration.
     *
     * Returns the instance that was live so the caller can shut it down. After
     * this a background engine reports `not_initialized` until the next
     * successful `initialize`, which is what an explicit shutdown means.
     */
    @Synchronized
    fun clear(context: Context): Analytics? {
        val current = instance
        instance = null
        identity = null
        preferences(context).edit().remove(KEY_CONFIGURATION).apply()
        securePreferences(context)?.edit()?.remove(KEY_WRITE_KEY)?.apply()
        return current
    }

    /**
     * Persists the configuration for a future background engine: the write key
     * into the encrypted file, everything else into plain preferences.
     *
     * Nothing is persisted at all when the write key cannot be encrypted, so
     * the two halves never disagree and no credential is written in the clear.
     */
    private fun persist(context: Context, source: Map<*, *>?) {
        val writeKey = (source?.get(KEY_WRITE_KEY) as? String)?.takeIf { it.isNotBlank() }
        val secure = writeKey?.let { securePreferences(context) }
        if (source == null || writeKey == null || secure == null) {
            if (writeKey != null) {
                Log.w(
                    TAG,
                    "Narya could not open encrypted storage, so the write key was not " +
                        "persisted. Push handling from a firebase_messaging background " +
                        "isolate will report not_initialized until Narya.initialize() runs " +
                        "in this process again.",
                )
            }
            clearPersisted(context)
            return
        }
        val redacted = source.filterKeys { it?.toString() != KEY_WRITE_KEY }
        secure.edit().putString(KEY_WRITE_KEY, writeKey).apply()
        preferences(context)
            .edit()
            .putString(KEY_CONFIGURATION, NaryaCodec.toJsonObject(redacted).toString())
            .apply()
    }

    private fun clearPersisted(context: Context) {
        preferences(context).edit().remove(KEY_CONFIGURATION).apply()
        securePreferences(context)?.edit()?.remove(KEY_WRITE_KEY)?.apply()
    }

    /**
     * Rebuilds the configuration map [persist] split in two, or `null` when
     * either half is missing or unusable.
     */
    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    private fun readPersisted(context: Context): Map<String, Any?>? {
        val raw = preferences(context).getString(KEY_CONFIGURATION, null) ?: return null
        val writeKey = securePreferences(context)
            ?.getString(KEY_WRITE_KEY, null)
            ?.takeIf { it.isNotBlank() }
        if (writeKey == null) {
            Log.w(TAG, "Persisted Narya write key is missing or unreadable; ignoring it")
            return null
        }
        val decoded = try {
            NaryaCodec.fromJsonObject(Json.parseToJsonElement(raw).jsonObject)
        } catch (error: Exception) {
            Log.w(TAG, "Persisted Narya configuration could not be parsed; ignoring it")
            null
        } ?: return null
        return decoded + (KEY_WRITE_KEY to writeKey)
    }

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    /**
     * The encrypted preferences file, opened once per process, or `null` when
     * this device cannot provide it.
     *
     * `EncryptedSharedPreferences` needs API 23, and an existing file becomes
     * undecryptable when it is restored onto another device or the keystore
     * loses the master key. Nothing in it is recoverable at that point, so the
     * file is deleted and reopened once - the same self-heal the native SDK's
     * `EncryptedKeyValueStore` performs - and the host simply re-runs
     * `Narya.initialize`, which persists the key again.
     */
    @Suppress("TooGenericExceptionCaught")
    private fun securePreferences(context: Context): SharedPreferences? {
        if (securePreferencesResolved) return securePreferences
        securePreferencesResolved = true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Log.w(
                TAG,
                "EncryptedSharedPreferences requires API 23; the Narya write key will not " +
                    "be persisted on this device.",
            )
            return null
        }
        val opened = try {
            openSecurePreferences(context)
        } catch (error: Exception) {
            Log.w(
                TAG,
                "Encrypted Narya storage could not be opened; deleting it and starting fresh",
                error,
            )
            deleteSecurePreferences(context)
            try {
                openSecurePreferences(context)
            } catch (retryError: Exception) {
                Log.w(TAG, "Encrypted Narya storage is unavailable on this device", retryError)
                null
            }
        }
        securePreferences = opened
        return opened
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun openSecurePreferences(context: Context): SharedPreferences {
        val application = context.applicationContext
        val masterKey = MasterKey.Builder(application)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            application,
            PREFERENCES_SECURE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    private fun deleteSecurePreferences(context: Context) {
        val application = context.applicationContext
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                application.deleteSharedPreferences(PREFERENCES_SECURE)
            } else {
                File(
                    "${application.applicationInfo.dataDir}/shared_prefs/$PREFERENCES_SECURE.xml",
                ).takeIf { it.exists() }?.delete()
            }
        } catch (error: Exception) {
            Log.w(TAG, "Encrypted Narya storage could not be deleted")
        }
    }
}
