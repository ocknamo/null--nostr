package io.nurunuru.app.ui.miniapps

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.fetchMuteList
import io.nurunuru.app.data.removeFromMuteList
import io.nurunuru.app.data.models.MuteListData
import io.nurunuru.app.data.models.UserProfile
import io.nurunuru.app.ui.components.UserAvatar
import io.nurunuru.app.ui.theme.LocalNuruColors
import kotlinx.coroutines.launch

@Composable
fun MuteList(
    pubkey: String,
    repository: NostrRepository
) {
    val nuruColors = LocalNuruColors.current
    val scope = rememberCoroutineScope()

    var muteList by remember { mutableStateOf(MuteListData()) }
    var mutedProfiles by remember { mutableStateOf<Map<String, UserProfile>>(emptyMap()) }
    var isLoading by remember { mutableStateOf(true) }
    var removingValue by remember { mutableStateOf<String?>(null) }

    fun reload() {
        scope.launch {
            isLoading = true
            try {
                val list = repository.fetchMuteList(pubkey)
                muteList = list
                val pks = (list.privatePubkeys + list.publicPubkeys + list.pubkeys).distinct()
                mutedProfiles = if (pks.isNotEmpty()) repository.fetchProfiles(pks) else emptyMap()
            } catch (e: Exception) {
                android.util.Log.e("MuteList", "Failed to fetch mute list", e)
            } finally {
                isLoading = false
            }
        }
    }

    LaunchedEffect(pubkey) { reload() }

    val handleUnmute = { type: String, value: String ->
        if (removingValue == null) {
            removingValue = value
            scope.launch {
                try {
                    if (repository.removeFromMuteList(pubkey, type, value)) {
                        muteList = repository.fetchMuteList(pubkey)
                        val pks = (muteList.privatePubkeys + muteList.publicPubkeys + muteList.pubkeys).distinct()
                        mutedProfiles = if (pks.isNotEmpty()) repository.fetchProfiles(pks) else emptyMap()
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MuteList", "Failed to unmute $value", e)
                } finally {
                    removingValue = null
                }
            }
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(nuruColors.bgPrimary),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp)
    ) {
        if (isLoading) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 40.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text("読み込み中...", color = nuruColors.textTertiary, fontSize = 14.sp)
                }
            }
        }

        item {
            MuteSectionHeader(
                icon = { Icon(Icons.Outlined.Lock, null, tint = nuruColors.textSecondary, modifier = Modifier.size(22.dp)) },
                title = "非公開ミュート (NIP-44 暗号化)"
            )
            Spacer(Modifier.height(12.dp))
            AddMuteButton(text = "非公開でユーザーを追加")
            if (!isLoading && muteList.privatePubkeys.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    muteList.privatePubkeys.forEach { pk ->
                        MutedUserRow(
                            pubkey = pk,
                            profile = mutedProfiles[pk],
                            isRemoving = removingValue == pk,
                            onUnmute = { handleUnmute("privatePubkey", pk) }
                        )
                    }
                }
            }
        }

        item {
            MuteSectionHeader(
                icon = { Icon(Icons.Default.VisibilityOff, null, tint = nuruColors.textSecondary, modifier = Modifier.size(22.dp)) },
                title = "公開ミュート"
            )
            Spacer(Modifier.height(12.dp))
            AddMuteButton(text = "公開でユーザーを追加")
            if (!isLoading && muteList.publicPubkeys.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    muteList.publicPubkeys.forEach { pk ->
                        MutedUserRow(
                            pubkey = pk,
                            profile = mutedProfiles[pk],
                            isRemoving = removingValue == pk,
                            onUnmute = { handleUnmute("publicPubkey", pk) }
                        )
                    }
                }
            }
        }

        item {
            MuteSectionHeader(title = "ミュートキーワード")
            Spacer(Modifier.height(12.dp))
            AddMuteButton(text = "キーワードを追加")
            if (!isLoading && (muteList.words.isNotEmpty() || muteList.hashtags.isNotEmpty())) {
                Spacer(Modifier.height(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    muteList.words.forEach { word ->
                        MutedKeywordRow(
                            label = word,
                            isRemoving = removingValue == word,
                            onUnmute = { handleUnmute("word", word) }
                        )
                    }
                    muteList.hashtags.forEach { tag ->
                        MutedKeywordRow(
                            label = "#$tag",
                            isRemoving = removingValue == tag,
                            onUnmute = { handleUnmute("hashtag", tag) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MuteSectionHeader(
    title: String,
    icon: (@Composable () -> Unit)? = null
) {
    val nuruColors = LocalNuruColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        if (icon != null) icon()
        Text(
            text = title,
            color = nuruColors.textSecondary,
            fontWeight = FontWeight.Bold,
            fontSize = 18.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun AddMuteButton(text: String) {
    val nuruColors = LocalNuruColors.current
    Surface(
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(28.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Icon(Icons.Default.Add, contentDescription = null, tint = nuruColors.lineGreen, modifier = Modifier.size(24.dp))
            Text(text = text, color = nuruColors.lineGreen, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun MutedUserRow(
    pubkey: String,
    profile: UserProfile?,
    isRemoving: Boolean,
    onUnmute: () -> Unit
) {
    val nuruColors = LocalNuruColors.current
    Surface(
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            UserAvatar(
                pictureUrl = profile?.picture,
                displayName = profile?.displayedName ?: "",
                size = 36.dp
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = profile?.displayedName ?: pubkey.take(8) + "...",
                    fontSize = 14.sp,
                    color = nuruColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = pubkey.take(12) + "...",
                    fontSize = 11.sp,
                    color = nuruColors.textTertiary,
                    maxLines = 1
                )
            }
            TextButton(onClick = onUnmute, enabled = !isRemoving) {
                Text(if (isRemoving) "..." else "解除", color = nuruColors.error, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun MutedKeywordRow(
    label: String,
    isRemoving: Boolean,
    onUnmute: () -> Unit
) {
    val nuruColors = LocalNuruColors.current
    Surface(
        color = nuruColors.bgSecondary,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(label, fontSize = 14.sp, color = nuruColors.textPrimary, modifier = Modifier.weight(1f))
            IconButton(onClick = onUnmute, enabled = !isRemoving) {
                Icon(Icons.Default.Close, contentDescription = "解除", tint = nuruColors.error, modifier = Modifier.size(18.dp))
            }
        }
    }
}
