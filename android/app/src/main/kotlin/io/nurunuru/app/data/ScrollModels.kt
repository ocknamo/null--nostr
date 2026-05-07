package io.nurunuru.app.data

import io.nurunuru.app.data.models.NostrEvent

/** NIP-A5 Scroll parameter definition parsed from a ["param", ...] tag. */
data class ScrollParam(
    val name: String,
    val description: String,
    val type: String,
    val required: Boolean
)

/**
 * NIP-A5 Scroll event (kind 1227).
 *
 * The WASM payload is stored in [wasmBase64] (event.content). Parsing is
 * intentionally fail-safe: invalid or incomplete tags are skipped instead of
 * crashing the mini-app list.
 */
data class ScrollEvent(
    val id: String,
    val pubkey: String,
    val title: String,
    val description: String,
    val wasmBase64: String,
    val params: List<ScrollParam>,
    val createdAt: Long
) {
    companion object {
        const val KIND_SCROLL = 1227
        const val KIND_FAVORITE_SCROLLS = 10027

        fun fromNostrEvent(event: NostrEvent): ScrollEvent? {
            if (event.kind != KIND_SCROLL) return null

            val params = event.tags.mapNotNull { tag ->
                if (tag.firstOrNull() != "param") return@mapNotNull null
                val name = tag.getOrNull(1)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                ScrollParam(
                    name = name,
                    description = tag.getOrNull(2).orEmpty(),
                    type = tag.getOrNull(3)?.takeIf { it.isNotBlank() } ?: "string",
                    required = tag.getOrNull(4)?.equals("true", ignoreCase = true) == true
                )
            }

            return ScrollEvent(
                id = event.id,
                pubkey = event.pubkey,
                title = event.getTagValue("title")?.takeIf { it.isNotBlank() } ?: "無題のスクロール",
                description = event.getTagValue("description").orEmpty(),
                wasmBase64 = event.content,
                params = params,
                createdAt = event.createdAt
            )
        }
    }
}
