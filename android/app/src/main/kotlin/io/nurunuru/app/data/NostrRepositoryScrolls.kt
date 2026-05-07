package io.nurunuru.app.data

import io.nurunuru.app.data.models.NostrEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Fetch NIP-A5 Scroll definitions (kind 1227). */
suspend fun NostrRepository.fetchScrolls(limit: Int = 50): List<ScrollEvent> = withContext(Dispatchers.IO) {
    val events = client.fetchEvents(
        NostrClient.Filter(
            kinds = listOf(ScrollEvent.KIND_SCROLL),
            limit = limit
        ),
        timeoutMs = 8_000
    )

    events
        .mapNotNull { event ->
            try { ScrollEvent.fromNostrEvent(event) } catch (_: Exception) { null }
        }
        .distinctBy { it.id }
        .sortedByDescending { it.createdAt }
}

/** Fetch the user's NIP-A5 favorite Scroll ids from kind 10027. */
suspend fun NostrRepository.fetchFavoriteScrolls(pubkeyHex: String): List<String> = withContext(Dispatchers.IO) {
    val events = client.fetchEvents(
        NostrClient.Filter(
            kinds = listOf(ScrollEvent.KIND_FAVORITE_SCROLLS),
            authors = listOf(pubkeyHex),
            limit = 1
        ),
        timeoutMs = 4_000
    )

    events.maxByOrNull { it.createdAt }
        ?.getTagValues("e")
        .orEmpty()
}

/** Add a Scroll to the user's favorite list (kind 10027). Idempotent. */
suspend fun NostrRepository.addFavoriteScroll(pubkeyHex: String, scrollId: String) {
    val existing = fetchFavoriteScrolls(pubkeyHex).toMutableList()
    if (scrollId in existing) return
    existing.add(scrollId)
    publishFavoriteScrolls(existing)
}

/** Remove a Scroll from the user's favorite list (kind 10027). Idempotent. */
suspend fun NostrRepository.removeFavoriteScroll(pubkeyHex: String, scrollId: String) {
    val existing = fetchFavoriteScrolls(pubkeyHex).toMutableList()
    val changed = existing.removeAll { it == scrollId }
    if (!changed) return
    publishFavoriteScrolls(existing)
}

private suspend fun NostrRepository.publishFavoriteScrolls(scrollIds: List<String>): NostrEvent? {
    val tags = scrollIds.distinct().map { listOf("e", it) }
    return publishEvent(
        kind = ScrollEvent.KIND_FAVORITE_SCROLLS,
        content = "",
        tags = tags
    )
}
