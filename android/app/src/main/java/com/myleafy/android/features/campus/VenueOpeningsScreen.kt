package com.myleafy.android.features.campus

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.myleafy.android.ui.components.*

@Composable fun VenueOpeningsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val groups = remember { CampusVenueGroup.load(context) }
    var collapsedGroups by rememberSaveable { mutableStateOf(groups.map { it.id }) }
    var expanded by rememberSaveable { mutableStateOf(emptyList<String>()) }
    LeafySecondaryScaffold("场馆开放", onBack = onBack) { modifier ->
        LazyColumn(modifier, contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text("北林场馆资料 · 本地整理日期 2026-10-01。开放、价格及预约以学校通知和场馆现场为准。", style = MaterialTheme.typography.bodySmall) }
            groups.forEach { group ->
                item(key = group.id) { TextButton(onClick = { collapsedGroups = if (group.id in collapsedGroups) collapsedGroups - group.id else collapsedGroups + group.id }) { Text("${group.title} · ${group.venues.size} 处 ${if (group.id in collapsedGroups) "›" else "⌄"}", style = MaterialTheme.typography.titleMedium) } }
                if (group.id !in collapsedGroups)
                items(group.venues, key = { it.id }) { venue ->
                    LeafyContentSurface(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Column(Modifier.fillMaxWidth().clickable {
                                expanded = if (venue.id in expanded) expanded - venue.id else (expanded - group.venues.map { it.id }.toSet()) + venue.id
                            }) {
                                Text("${venue.title} ${if (venue.id in expanded) "⌄" else "›"}", style = MaterialTheme.typography.titleMedium)
                                Text(venue.location)
                                Text(venue.tags.joinToString(" · "), style = MaterialTheme.typography.bodySmall)
                            }
                            if (venue.id in expanded) {
                                venue.details.forEach { Text("${it.title}：${it.value}") }
                                venue.fees.forEach { fee -> Text(fee.title, style = MaterialTheme.typography.titleSmall); fee.lines.forEach { Text("${it.title}：${it.value}") } }
                                venue.notes.forEach { Text("• $it", style = MaterialTheme.typography.bodyMedium) }
                            }
                        }
                    }
                }
            }
        }
    }
}
