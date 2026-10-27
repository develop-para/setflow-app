package com.teampara.setflow

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * A device-local performed-record journal. This never opens Flutter's Hive files.
 * Projection, completion cursor and receipt are committed in one preference write;
 * an action is not shown as complete if that durable write fails.
 */
object WorkoutLockScreenStore {
    private const val PREFERENCES = "setflow_lock_screen_workout"
    private const val ROOT = "journal_v1"
    private const val GUEST = "guest_owner_key"
    private const val MAX_UNACKNOWLEDGED = 256

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun load(context: Context): JSONObject {
        val encoded = preferences(context).getString(ROOT, null) ?: return JSONObject()
        return try {
            JSONObject(encoded)
        } catch (error: Exception) {
            // Corrupt receipts must never be silently overwritten by a new plan.
            throw IllegalStateException("Workout journal could not be read", error)
        }
    }

    private fun commit(context: Context, root: JSONObject) {
        check(preferences(context).edit().putString(ROOT, root.toString()).commit()) {
            "Workout record could not be stored"
        }
    }

    @Synchronized
    fun guestOwnerKey(context: Context): String {
        preferences(context).getString(GUEST, null)?.let { return it }
        val owner = "guest_${UUID.randomUUID()}"
        check(preferences(context).edit().putString(GUEST, owner).commit())
        return owner
    }

    @Synchronized
    fun publish(context: Context, payload: Map<*, *>): Boolean {
        val state = JSONObject(payload)
        require(state.optInt("schemaVersion") == 1)
        require(state.optString("sessionId").isNotBlank())
        require(state.optString("ownerKey").isNotBlank())
        require(state.optJSONArray("sets") != null)
        require(isFresh(state)) { "Workout projection has expired" }
        val root = load(context)
        val pending = root.optJSONArray("events") ?: JSONArray()
        for (index in 0 until pending.length()) {
            if (pending.optJSONObject(index)?.optString("ownerKey") == state.optString("ownerKey")) {
                // A notification tap may commit after Dart readEvents but before
                // its next publish. Keep that exact cursor until Dart ingests
                // and acknowledges it, rather than replacing performed history.
                return false
            }
        }
        val previous = root.optJSONObject("state")
        if (previous?.optString("sessionId") != state.optString("sessionId") ||
            previous?.optString("ownerKey") != state.optString("ownerKey")
        ) {
            root.put("completed", JSONArray())
            root.put("restEndsAtMillis", 0L)
        }
        root.put("state", state)
        if (state.has("restEndsAtMillis")) {
            root.put("restEndsAtMillis", state.optLong("restEndsAtMillis"))
        }
        commit(context, root)
        return true
    }

    @Synchronized
    fun clear(context: Context) {
        val root = load(context)
        root.remove("state")
        root.remove("restEndsAtMillis")
        // Retain both unacknowledged records and their deduplication tokens.
        commit(context, root)
    }

    @Synchronized
    fun state(context: Context): JSONObject? = load(context).optJSONObject("state")
        ?.takeIf(::isFresh)

    @Synchronized
    fun currentSet(context: Context): JSONObject? = currentSet(load(context))

    private fun currentSet(root: JSONObject): JSONObject? {
        val state = root.optJSONObject("state")?.takeIf(::isFresh) ?: return null
        val completed = root.optJSONArray("completed") ?: JSONArray()
        val tokens = (0 until completed.length()).map { completed.optString(it) }.toSet()
        val sets = state.optJSONArray("sets") ?: return null
        for (index in 0 until sets.length()) {
            val set = sets.optJSONObject(index) ?: continue
            if (set.optString("token") !in tokens) return set
        }
        return null
    }

    @Synchronized
    fun restEndsAt(context: Context): Long = load(context).optLong("restEndsAtMillis")

    @Synchronized
    fun setRestEndsAt(context: Context, endsAtMillis: Long) {
        val root = load(context)
        if (root.optJSONObject("state") == null) return
        root.put("restEndsAtMillis", endsAtMillis)
        commit(context, root)
    }

    @Synchronized
    fun complete(context: Context, sessionId: String?, token: String?): JSONObject? {
        val root = load(context)
        val state = root.optJSONObject("state")?.takeIf(::isFresh) ?: return null
        if (sessionId != state.optString("sessionId") || token.isNullOrBlank()) return null
        if (root.optLong("restEndsAtMillis") > System.currentTimeMillis()) return null
        val set = currentSet(root) ?: return null
        if (set.optString("token") != token || !set.optBoolean("canComplete")) return null
        val events = root.optJSONArray("events") ?: JSONArray()
        if (events.length() >= MAX_UNACKNOWLEDGED) return null
        val now = System.currentTimeMillis()
        val restSeconds = if (state.optBoolean("autoStartRestTimer")) {
            set.optInt("restSeconds").coerceIn(0, 3_600)
        } else 0
        val deadline = if (restSeconds > 0) now + restSeconds * 1_000L else 0L
        val event = JSONObject()
            .put("eventId", UUID.randomUUID().toString())
            .put("sessionId", sessionId)
            .put("ownerKey", state.optString("ownerKey"))
            .put("workoutDate", state.optString("workoutDate"))
            .put("publishedAtMillis", state.optLong("publishedAtMillis"))
            .put("expiresAtMillis", state.optLong("expiresAtMillis"))
            .put("completedAtMillis", now)
            .put("restEndsAtMillis", deadline)
            .put("set", JSONObject(set.toString()))
        events.put(event)
        val completed = root.optJSONArray("completed") ?: JSONArray()
        completed.put(token)
        root.put("events", events)
        root.put("completed", completed)
        root.put("restEndsAtMillis", deadline)
        commit(context, root)
        return event
    }

    @Synchronized
    fun readEvents(context: Context): List<Map<String, Any?>> {
        val events = load(context).optJSONArray("events") ?: JSONArray()
        return (0 until events.length()).mapNotNull { index ->
            events.optJSONObject(index)?.let(::asMap)
        }
    }

    @Synchronized
    fun acknowledge(context: Context, eventIds: Set<String>) {
        val root = load(context)
        val events = root.optJSONArray("events") ?: JSONArray()
        val retained = JSONArray()
        for (index in 0 until events.length()) {
            val event = events.optJSONObject(index) ?: continue
            if (event.optString("eventId") !in eventIds) retained.put(event)
        }
        root.put("events", retained)
        commit(context, root)
    }

    private fun isFresh(state: JSONObject): Boolean {
        val now = System.currentTimeMillis()
        return state.optLong("publishedAtMillis") <= now &&
            state.optLong("expiresAtMillis") > now &&
            state.optString("workoutDate") ==
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
    }

    private fun asMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence()
        .associateWith { key -> asChannelValue(json.opt(key)) }

    private fun asChannelValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> asMap(value)
        is JSONArray -> (0 until value.length()).map { asChannelValue(value.opt(it)) }
        else -> value
    }
}
