package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces

/**
 * 周末去哪（北林）：内置周边出行推荐，按当季匹配度排序，不请求网络。
 * 推荐为静态整理，出行前请以官方信息为准。
 */
@Composable
fun WeekendTravelSection(modifier: Modifier = Modifier) {
    val recommendations = remember { WeekendTravelRecommendationEngine.recommend() }
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(LeafySpacing.page),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        item {
            LeafyStatusBanner(
                message = "推荐为静态整理，按当季匹配度排序；出行前请以交通与景区官方信息为准。",
                isError = false,
            )
        }
        item {
            LeafySectionHeader(
                title = "周末去哪",
                supportingText = "北京周边适合周末出行的目的地。",
            )
        }
        items(recommendations, key = { it.id }) { destination ->
            LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(LeafySpacing.card),
                    verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                ) {
                    Text(destination.cityName, style = MaterialTheme.typography.titleLarge)
                    Text(
                        destination.tagline,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                        TripMetric("路程", destination.travelTimeText)
                        TripMetric("建议", destination.tripLengthText)
                        TripMetric("预算", destination.budgetText)
                        TripMetric("季节", destination.seasonText + " 月")
                    }
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.tiny)) {
                        items(destination.highlightRail) { highlight ->
                            Surface(
                                shape = MaterialTheme.shapes.small,
                                color = MaterialTheme.leafySurfaces.accentSoft,
                            ) {
                                Text(
                                    text = highlight,
                                    style = MaterialTheme.typography.labelMedium,
                                    modifier = Modifier.padding(
                                        horizontal = LeafySpacing.micro,
                                        vertical = LeafySpacing.tiny,
                                    ),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TripMetric(label: String, value: String) {
    Column {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.labelLarge)
    }
}
