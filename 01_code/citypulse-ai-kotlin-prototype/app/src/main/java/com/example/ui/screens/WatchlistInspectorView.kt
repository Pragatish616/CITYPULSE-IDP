package com.example.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WaterDamage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.data.ChennaiGraphData
import com.example.model.EdgeBelief
import com.example.model.HazardCategory
import com.example.model.HazardObservation
import com.example.ui.theme.AppBackground
import com.example.ui.theme.HazardCrimson
import com.example.ui.theme.PrimaryGreen
import com.example.ui.theme.PrimaryGreenDark
import com.example.ui.theme.PrimaryGreenLight
import com.example.ui.theme.SurfaceBorder
import com.example.ui.theme.SurfaceCardAlt
import com.example.ui.theme.SurfaceLight
import com.example.ui.theme.TextMuted
import com.example.ui.theme.TextPrimary
import com.example.ui.theme.TextSecondary
import com.example.ui.theme.WarningAmber
import kotlin.math.roundToInt

@Composable
fun WatchlistInspectorView(
    edgeBeliefs: Map<String, EdgeBelief>,
    activeInspectedEdgeId: String?,
    observations: List<HazardObservation>,
    onSelectEdgeToInspect: (String) -> Unit,
    onSubmitReport: (edgeId: String, category: HazardCategory, depthCm: Int, desc: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var showReportDialog by remember { mutableStateOf(false) }

    val inspectedEdge = activeInspectedEdgeId?.let { ChennaiGraphData.EDGE_MAP[it] } ?: ChennaiGraphData.EDGES.first()
    val inspectedBelief = edgeBeliefs[inspectedEdge.id]

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(AppBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 1. Header & Report Waterlogging Action
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Chennai Flood Watchlist",
                        color = TextPrimary,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Known waterlogged subways & low-lying areas",
                        color = TextSecondary,
                        fontSize = 12.sp
                    )
                }

                Button(
                    onClick = { showReportDialog = true },
                    colors = ButtonDefaults.buttonColors(containerColor = PrimaryGreen),
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.testTag("report_incident_button")
                ) {
                    Icon(imageVector = Icons.Default.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(text = "Report Flood", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }
        }

        // 2. Selected Spot Status Card (Citizen-Friendly)
        item {
            SpotStatusCard(
                edge = inspectedEdge,
                belief = inspectedBelief
            )
        }

        // 3. Official GCC Watchlist Spots
        item {
            Text(
                text = "Monitored Subways & Low-Lying Corridors",
                color = TextPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold
            )
        }

        items(ChennaiGraphData.CHENNAI_WATCHLIST) { spot ->
            val belief = edgeBeliefs[spot.edgeId]
            val isSelected = spot.edgeId == activeInspectedEdgeId

            WatchlistSpotCard(
                spot = spot,
                belief = belief,
                isSelected = isSelected,
                onClick = { onSelectEdgeToInspect(spot.edgeId) }
            )
        }
    }

    if (showReportDialog) {
        ReportHazardDialog(
            onDismiss = { showReportDialog = false },
            onSubmit = { edgeId, category, depthCm, desc ->
                onSubmitReport(edgeId, category, depthCm, desc)
                showReportDialog = false
            }
        )
    }
}

@Composable
private fun SpotStatusCard(
    edge: com.example.model.RoadEdge,
    belief: EdgeBelief?
) {
    val pTilde = belief?.pessimisticProbabilityPTilde ?: 0.1
    val isSevered = belief?.isSeveredByChanceConstraint ?: false
    var showDetails by remember { mutableStateOf(false) }

    Card(
        colors = CardDefaults.cardColors(containerColor = SurfaceLight),
        shape = RoundedCornerShape(16.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, SurfaceBorder, RoundedCornerShape(16.dp))
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Selected Road Status",
                        color = TextSecondary,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = edge.roadName,
                        color = TextPrimary,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Surface(
                    color = if (isSevered || pTilde > 0.6) HazardCrimson.copy(alpha = 0.12f) else PrimaryGreenLight,
                    shape = RoundedCornerShape(8.dp),
                    modifier = Modifier.border(
                        1.dp,
                        if (isSevered || pTilde > 0.6) HazardCrimson else PrimaryGreen,
                        RoundedCornerShape(8.dp)
                    )
                ) {
                    Text(
                        text = if (isSevered) "AVOID ROAD" else if (pTilde > 0.5) "HIGH WATER" else "OPEN / SAFE",
                        color = if (isSevered || pTilde > 0.6) HazardCrimson else PrimaryGreenDark,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Surface(
                color = SurfaceCardAlt,
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(text = "Terrain Type", color = TextSecondary, fontSize = 12.sp)
                        Text(text = edge.terrainPrior.label, color = TextPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(text = "Flooding Probability", color = TextSecondary, fontSize = 12.sp)
                        Text(
                            text = "${(pTilde * 100).roundToInt()}% risk level",
                            color = if (pTilde > 0.6) HazardCrimson else PrimaryGreenDark,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(10.dp))

            // Plain explanation for common citizen
            Text(
                text = if (isSevered)
                    "This road has reached water levels dangerous for vehicles and has been closed or removed from recommended routes."
                else
                    "CityPulse monitors this road continuously using GCC historical rainfall curves.",
                color = TextSecondary,
                fontSize = 12.sp,
                lineHeight = 17.sp
            )
        }
    }
}

@Composable
private fun WatchlistSpotCard(
    spot: ChennaiGraphData.WatchlistSpot,
    belief: EdgeBelief?,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val pTilde = belief?.pessimisticProbabilityPTilde ?: 0.1
    val isSevered = belief?.isSeveredByChanceConstraint ?: false

    Card(
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) PrimaryGreenLight else SurfaceLight
        ),
        shape = RoundedCornerShape(14.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = if (isSelected) 2.dp else 1.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .border(
                width = if (isSelected) 2.dp else 1.dp,
                color = if (isSelected) PrimaryGreen else SurfaceBorder,
                shape = RoundedCornerShape(14.dp)
            )
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(if (isSevered || pTilde > 0.6) HazardCrimson else if (pTilde > 0.3) WarningAmber else PrimaryGreen)
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = spot.title,
                        color = TextPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                }

                Text(
                    text = if (isSevered) "CLOSED" else "${(pTilde * 100).roundToInt()}% Risk",
                    color = if (isSevered || pTilde > 0.6) HazardCrimson else if (pTilde > 0.3) WarningAmber else PrimaryGreenDark,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = spot.floodVulnerabilityNote,
                color = TextSecondary,
                fontSize = 12.sp
            )

            if (belief?.primaryHazardNotice != null) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "Status: ${belief.primaryHazardNotice}",
                    color = PrimaryGreenDark,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

@Composable
private fun ReportHazardDialog(
    onDismiss: () -> Unit,
    onSubmit: (edgeId: String, category: HazardCategory, depthCm: Int, desc: String) -> Unit
) {
    var selectedEdgeId by remember { mutableStateOf("e_vyas_subway_fwd") }
    var selectedCategory by remember { mutableStateOf(HazardCategory.SUBWAY_INUNDATION) }
    var depthCm by remember { mutableIntStateOf(50) }
    var description by remember { mutableStateOf("Water pooling above ankle level") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "Report Flooded Road", color = TextPrimary, fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(text = "Location: Vyasarpadi Ganesapuram Subway", color = TextSecondary, fontSize = 13.sp)

                OutlinedTextField(
                    value = depthCm.toString(),
                    onValueChange = { depthCm = it.toIntOrNull() ?: 0 },
                    label = { Text("Water Depth (approx. cm)") },
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("What do you see?") },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onSubmit(selectedEdgeId, selectedCategory, depthCm, description) },
                colors = ButtonDefaults.buttonColors(containerColor = PrimaryGreen)
            ) {
                Text(text = "Submit Report", color = Color.White, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(text = "Cancel", color = TextSecondary)
            }
        },
        containerColor = SurfaceLight
    )
}
