package com.example.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.example.data.ChennaiBuildingData
import com.example.data.ChennaiGraphData
import com.example.model.BuildingType
import com.example.model.EdgeBelief
import com.example.model.GeoPoint
import com.example.model.MapBuilding
import com.example.model.RoadNode
import com.example.model.RouteResult
import com.example.ui.theme.ElevatedPurple
import com.example.ui.theme.HazardCrimson
import com.example.ui.theme.InundatedDeepBlue
import com.example.ui.theme.NaiveRouteDanger
import com.example.ui.theme.PrimaryGreen
import com.example.ui.theme.PrimaryGreenDark
import com.example.ui.theme.PrimaryGreenLight
import com.example.ui.theme.SafeEmerald
import com.example.ui.theme.SurfaceBorder
import com.example.ui.theme.SurfaceCardAlt
import com.example.ui.theme.SurfaceLight
import com.example.ui.theme.TextMuted
import com.example.ui.theme.TextPrimary
import com.example.ui.theme.TextSecondary
import com.example.ui.theme.WarningAmber
import kotlin.math.cos
import kotlin.math.sin

// Light theme green, white, and black map canvas colors
private val MapBgLight = Color(0xFFFFFFFF) // Pure crisp white canvas
private val MapOceanLight = Color(0xFFEBF5FB) // Clean soft water tone for Bay of Bengal
private val MapBeachLight = Color(0xFFF9F7F2) // Soft clean shoreline
private val MapRiverLight = Color(0xFFA0BCC2) // Clean visible river color
private val RoadBaseColor = Color(0xFFF1F5F9) // Clean road casing
private val RoadNormalColor = Color(0xFF475569) // Sharp slate-dark road lines on white canvas

@Composable
fun InteractiveMapView(
    originNodeId: String,
    destNodeId: String,
    edgeBeliefs: Map<String, EdgeBelief>,
    naiveRoute: RouteResult?,
    cityPulseRoute: RouteResult?,
    isOffline: Boolean,
    onSelectOrigin: (String) -> Unit,
    onSelectDest: (String) -> Unit,
    onSwap: () -> Unit,
    onInspectEdge: (String) -> Unit,
    onToggleOffline: () -> Unit,
    onNavigateToExplanation: () -> Unit,
    modifier: Modifier = Modifier
) {
    var selectedNodeForAction by remember { mutableStateOf<RoadNode?>(null) }
    var showOriginPicker by remember { mutableStateOf(false) }
    var showDestPicker by remember { mutableStateOf(false) }
    var showAllBuildings by remember { mutableStateOf(true) }
    var isLegendExpanded by remember { mutableStateOf(false) }

    // Transform / Pan & Zoom state
    var zoomScale by remember { mutableFloatStateOf(1.0f) }
    var panOffset by remember { mutableStateOf(Offset.Zero) }

    val transformState = rememberTransformableState { zoomChange, offsetChange, _ ->
        zoomScale = (zoomScale * zoomChange).coerceIn(0.85f, 4.5f)
        panOffset += offsetChange
    }

    // Map geographic bounds in Chennai
    val minLat = 12.905
    val maxLat = 13.125
    val minLon = 80.075
    val maxLon = 80.295

    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAlpha"
    )

    val textMeasurer = rememberTextMeasurer()

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(MapBgLight)
    ) {
        val widthPx = constraints.maxWidth.toFloat()
        val heightPx = constraints.maxHeight.toFloat()
        val centerX = widthPx / 2f
        val centerY = heightPx / 2f

        // Projection mapping lat/lon to Canvas pixels with zoom & pan
        fun project(point: GeoPoint): Offset {
            val baseNormX = ((point.lon - minLon) / (maxLon - minLon)).toFloat()
            val baseNormY = (1.0f - ((point.lat - minLat) / (maxLat - minLat)).toFloat())

            val rawX = baseNormX * (widthPx - 80f) + 40f
            val rawY = baseNormY * (heightPx - 90f) + 45f

            // Scale around center
            val scaledX = (rawX - centerX) * zoomScale + centerX + panOffset.x
            val scaledY = (rawY - centerY) * zoomScale + centerY + panOffset.y

            return Offset(scaledX, scaledY)
        }

        // 1. FULL-BLEED CRISP LIGHT MAP CANVAS
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .transformable(state = transformState)
                .pointerInput(zoomScale, panOffset) {
                    detectTapGestures { tapOffset ->
                        var closestNode: RoadNode? = null
                        var minDist = 44f * zoomScale.coerceAtLeast(1f)

                        for (node in ChennaiGraphData.NODES) {
                            val nodePos = project(node.point)
                            val dist = (nodePos - tapOffset).getDistance()
                            if (dist < minDist) {
                                minDist = dist
                                closestNode = node
                            }
                        }

                        if (closestNode != null) {
                            selectedNodeForAction = closestNode
                        }
                    }
                }
        ) {
            // A. Geographic Water Features (Bay of Bengal, Adyar & Cooum Rivers, Lakes)
            drawChennaiGeographyLight(widthPx, heightPx, ::project)

            // B. Road Network Edges (Clean, crisp, light-mode visible)
            drawRoadEdgesLight(
                edgeBeliefs = edgeBeliefs,
                project = ::project,
                zoomScale = zoomScale
            )

            // C. 3D Architectural Buildings & Landmarks (Vibrant, high contrast, clearly visible)
            drawChennaiBuildingsLight(
                buildings = ChennaiBuildingData.BUILDINGS,
                showAll = showAllBuildings,
                zoomScale = zoomScale,
                project = ::project,
                textMeasurer = textMeasurer
            )

            // D. Naive Shortest Route (Dashed Red Line showing flood traps)
            if (naiveRoute != null && naiveRoute.isSuccess) {
                drawRoutePath(
                    nodeIds = naiveRoute.pathNodeIds,
                    project = ::project,
                    color = NaiveRouteDanger.copy(alpha = 0.85f),
                    strokeWidth = 3.5f * zoomScale.coerceIn(0.9f, 2.0f),
                    isDashed = true
                )
            }

            // E. CityPulse Hazard-Aware Route (Vibrant Solid Green Route Ribbon)
            if (cityPulseRoute != null && cityPulseRoute.isSuccess) {
                // Soft glowing outline
                drawRoutePath(
                    nodeIds = cityPulseRoute.pathNodeIds,
                    project = ::project,
                    color = PrimaryGreen.copy(alpha = 0.25f),
                    strokeWidth = 12f * zoomScale.coerceIn(0.9f, 2.0f),
                    isDashed = false
                )
                // Crisp bold green core path
                drawRoutePath(
                    nodeIds = cityPulseRoute.pathNodeIds,
                    project = ::project,
                    color = PrimaryGreen,
                    strokeWidth = 6f * zoomScale.coerceIn(0.9f, 2.0f),
                    isDashed = false
                )
            }

            // F. Transit Nodes & Start/End Pins
            drawTransitNodesLight(
                originNodeId = originNodeId,
                destNodeId = destNodeId,
                safeRouteNodeIds = cityPulseRoute?.pathNodeIds ?: emptyList(),
                pulseAlpha = pulseAlpha,
                zoomScale = zoomScale,
                project = ::project
            )
        }

        // 2. MINIMALIST FLOATING TOP ROUTE CAPSULE (Light card, dark text, clean borders)
        FloatingRouteCapsule(
            originId = originNodeId,
            destId = destNodeId,
            isOffline = isOffline,
            onOriginClick = { showOriginPicker = true },
            onDestClick = { showDestPicker = true },
            onSwap = onSwap,
            onToggleOffline = onToggleOffline,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 10.dp)
        )

        // 3. FLOATING MINIMAL MAP TOOLBAR (Right Side)
        Column(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 70.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Toggle Buildings
            MinimalIconButton(
                icon = Icons.Default.Apartment,
                contentDescription = "Toggle Buildings",
                isActive = showAllBuildings,
                onClick = { showAllBuildings = !showAllBuildings }
            )

            // Toggle Legend
            MinimalIconButton(
                icon = Icons.Default.Info,
                contentDescription = "Toggle Legend",
                isActive = isLegendExpanded,
                onClick = { isLegendExpanded = !isLegendExpanded }
            )

            // Recenter / Reset Zoom
            MinimalIconButton(
                icon = Icons.Default.MyLocation,
                contentDescription = "Reset Zoom",
                isActive = false,
                onClick = {
                    zoomScale = 1.0f
                    panOffset = Offset.Zero
                }
            )
        }

        // 4. EXPANDABLE COMPACT LEGEND (Minimalist Dropdown)
        AnimatedVisibility(
            visible = isLegendExpanded,
            enter = fadeIn() + slideInVertically { -20 },
            exit = fadeOut() + slideOutVertically { -20 },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 190.dp, end = 16.dp)
        ) {
            MinimalistLegendCard(onClose = { isLegendExpanded = false })
        }

        // 5. MINIMALIST FLOATING ROUTE SUMMARY (Bottom)
        if (cityPulseRoute != null && naiveRoute != null && cityPulseRoute.isSuccess) {
            MinimalFloatingRouteBar(
                safeRoute = cityPulseRoute,
                naiveRoute = naiveRoute,
                onViewExplanation = onNavigateToExplanation,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            )
        }

        // 6. NODE ACTION DIALOG (When tapped directly on map)
        selectedNodeForAction?.let { node ->
            MinimalNodeActionDialog(
                node = node,
                onSetOrigin = {
                    onSelectOrigin(node.id)
                    selectedNodeForAction = null
                },
                onSetDest = {
                    onSelectDest(node.id)
                    selectedNodeForAction = null
                },
                onDismiss = { selectedNodeForAction = null }
            )
        }

        // 7. LOCATION PICKER DIALOG (When tapping start/destination in top capsule)
        if (showOriginPicker) {
            LocationPickerDialog(
                title = "Choose Starting Point",
                currentNodeId = originNodeId,
                otherNodeId = destNodeId,
                onSelectNode = {
                    onSelectOrigin(it)
                    showOriginPicker = false
                },
                onDismiss = { showOriginPicker = false }
            )
        }

        if (showDestPicker) {
            LocationPickerDialog(
                title = "Choose Destination",
                currentNodeId = destNodeId,
                otherNodeId = originNodeId,
                onSelectNode = {
                    onSelectDest(it)
                    showDestPicker = false
                },
                onDismiss = { showDestPicker = false }
            )
        }
    }
}

/**
 * 3D Architectural Buildings & Landmarks with High Contrast and Visibility in Light Mode
 */
private fun DrawScope.drawChennaiBuildingsLight(
    buildings: List<MapBuilding>,
    showAll: Boolean,
    zoomScale: Float,
    project: (GeoPoint) -> Offset,
    textMeasurer: TextMeasurer
) {
    val visibleBuildings = if (showAll) buildings else buildings.filter { it.isProminentLandmark }

    for (b in visibleBuildings) {
        // Convert dimensions in km to projected delta
        val halfWLon = (b.widthKm / 108.15) * 0.5
        val halfHLat = (b.heightKm / 111.0) * 0.5

        val rad = (b.rotationDeg * Math.PI / 180.0).toFloat()
        val cosT = cos(rad)
        val sinT = sin(rad)

        // 4 base corner offsets rotated
        val corners = listOf(
            Pair(-halfWLon, -halfHLat),
            Pair(halfWLon, -halfHLat),
            Pair(halfWLon, halfHLat),
            Pair(-halfWLon, halfHLat)
        ).map { (dx, dy) ->
            val rx = dx * cosT - dy * sinT
            val ry = dx * sinT + dy * cosT
            project(GeoPoint(b.center.lat + ry, b.center.lon + rx))
        }

        if (corners.size < 4) continue

        // Isometric roof extrusion offset based on building stories & zoom
        val storyHeight = b.heightStories * 1.6f * zoomScale.coerceIn(0.9f, 2.2f)
        val roofOffset = Offset(-storyHeight * 0.7f, -storyHeight * 1.1f)

        val roofCorners = corners.map { it + roofOffset }

        // 1. Draw Ground Drop Shadow
        val shadowPath = Path().apply {
            moveTo(corners[0].x, corners[0].y)
            for (i in 1..3) lineTo(corners[i].x, corners[i].y)
            close()
        }
        drawPath(shadowPath, color = Color(0x28000000))

        // 2. Draw 2.5D Shaded Facades (Crisp architectural gray tones with depth)
        // South facade (0 -> 1)
        val southWall = Path().apply {
            moveTo(corners[0].x, corners[0].y)
            lineTo(corners[1].x, corners[1].y)
            lineTo(roofCorners[1].x, roofCorners[1].y)
            lineTo(roofCorners[0].x, roofCorners[0].y)
            close()
        }
        drawPath(southWall, color = Color(0xFFBAC3CC))

        // East facade (1 -> 2)
        val eastWall = Path().apply {
            moveTo(corners[1].x, corners[1].y)
            lineTo(corners[2].x, corners[2].y)
            lineTo(roofCorners[2].x, roofCorners[2].y)
            lineTo(roofCorners[1].x, roofCorners[1].y)
            close()
        }
        drawPath(eastWall, color = Color(0xFFCCD5DE))

        // West facade
        val westWall = Path().apply {
            moveTo(corners[3].x, corners[3].y)
            lineTo(corners[0].x, corners[0].y)
            lineTo(roofCorners[0].x, roofCorners[0].y)
            lineTo(roofCorners[3].x, roofCorners[3].y)
            close()
        }
        drawPath(westWall, color = Color(0xFFA6B0BA))

        // 3. Draw Roof Surface (Vibrant and high contrast so buildings pop against the light map)
        val roofPath = Path().apply {
            moveTo(roofCorners[0].x, roofCorners[0].y)
            for (i in 1..3) lineTo(roofCorners[i].x, roofCorners[i].y)
            close()
        }

        val (roofFill, roofStroke) = when (b.type) {
            BuildingType.TECH_PARK -> Pair(PrimaryGreenLight, PrimaryGreenDark) // Modern clean green
            BuildingType.TRANSIT_HUB -> Pair(PrimaryGreenLight, PrimaryGreen) // Green transit hub
            BuildingType.HERITAGE_LANDMARK -> Pair(Color.White, Color(0xFF111827)) // Crisp white & black heritage
            BuildingType.COMMERCIAL_TOWER -> Pair(Color(0xFFF8FAF9), Color(0xFF1E293B)) // Crisp monochrome tower
            BuildingType.INSTITUTIONAL -> Pair(Color.White, Color(0xFF374151)) // Crisp white institutional
            BuildingType.URBAN_RESIDENTIAL -> Pair(Color(0xFFF1F5F9), Color(0xFF64748B)) // Clean neutral slate
        }

        drawPath(roofPath, color = roofFill)
        drawPath(
            roofPath,
            color = if (b.isProminentLandmark) PrimaryGreen else roofStroke,
            style = Stroke(width = if (b.isProminentLandmark) 2.2f else 1.2f)
        )

        // 4. Rooftop Details & Clean White Label Badge
        val roofCenter = Offset(
            (roofCorners[0].x + roofCorners[2].x) / 2f,
            (roofCorners[0].y + roofCorners[2].y) / 2f
        )

        if (b.isProminentLandmark) {
            // Roof spire / architectural indicator in green
            drawCircle(
                color = PrimaryGreen,
                radius = 3.5f * zoomScale.coerceIn(0.9f, 1.8f),
                center = roofCenter
            )

            // 5. Clean, legible Landmark Label Pill (White pill, Green border, Black text)
            val shortName = b.name.take(20)
            val textLayoutResult = textMeasurer.measure(
                text = shortName,
                style = TextStyle(
                    color = Color(0xFF000000),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.SansSerif
                )
            )

            val badgeW = textLayoutResult.size.width.toFloat() + 16f
            val badgeH = textLayoutResult.size.height.toFloat() + 8f
            val badgePos = Offset(roofCenter.x - badgeW / 2f, roofCenter.y - badgeH - 6f)

            // Draw crisp white pill with shadow
            drawRoundRect(
                color = Color(0x22000000),
                topLeft = Offset(badgePos.x, badgePos.y + 2f),
                size = Size(badgeW, badgeH),
                cornerRadius = CornerRadius(8f, 8f)
            )
            drawRoundRect(
                color = Color.White,
                topLeft = badgePos,
                size = Size(badgeW, badgeH),
                cornerRadius = CornerRadius(8f, 8f)
            )
            drawRoundRect(
                color = PrimaryGreen,
                topLeft = badgePos,
                size = Size(badgeW, badgeH),
                cornerRadius = CornerRadius(8f, 8f),
                style = Stroke(width = 1.4f)
            )

            // Draw label text
            drawText(
                textLayoutResult = textLayoutResult,
                topLeft = Offset(badgePos.x + 8f, badgePos.y + 4f)
            )
        }
    }
}

/**
 * Draw road network edges with high contrast light styling and hazard signals
 */
private fun DrawScope.drawRoadEdgesLight(
    edgeBeliefs: Map<String, EdgeBelief>,
    project: (GeoPoint) -> Offset,
    zoomScale: Float
) {
    // 1. Casing for crisp visual hierarchy
    for (edge in ChennaiGraphData.EDGES) {
        val fromNode = ChennaiGraphData.NODE_MAP[edge.fromNodeId] ?: continue
        val toNode = ChennaiGraphData.NODE_MAP[edge.toNodeId] ?: continue

        val start = project(fromNode.point)
        val end = project(toNode.point)

        drawLine(
            color = RoadBaseColor,
            start = start,
            end = end,
            strokeWidth = 4.5f * zoomScale.coerceIn(0.8f, 1.6f),
            cap = StrokeCap.Round
        )
    }

    // 2. Active colored status roads
    for (edge in ChennaiGraphData.EDGES) {
        val fromNode = ChennaiGraphData.NODE_MAP[edge.fromNodeId] ?: continue
        val toNode = ChennaiGraphData.NODE_MAP[edge.toNodeId] ?: continue

        val start = project(fromNode.point)
        val end = project(toNode.point)

        val belief = edgeBeliefs[edge.id]
        val pTilde = belief?.pessimisticProbabilityPTilde ?: 0.1
        val isSevered = belief?.isSeveredByChanceConstraint ?: false

        val edgeColor = when {
            isSevered -> HazardCrimson
            pTilde > 0.65 -> HazardCrimson.copy(alpha = 0.9f)
            pTilde > 0.35 -> WarningAmber.copy(alpha = 0.9f)
            edge.isElevatedCorridor -> ElevatedPurple.copy(alpha = 0.85f)
            else -> RoadNormalColor
        }

        val strokeWidth = if (edge.isElevatedCorridor) 3.6f else 2.4f

        drawLine(
            color = edgeColor,
            start = start,
            end = end,
            strokeWidth = strokeWidth * zoomScale.coerceIn(0.8f, 1.8f),
            cap = StrokeCap.Round
        )

        // Severed Hazard Chokepoint (Subway Inundation) Marker
        if (isSevered) {
            val mid = Offset((start.x + end.x) / 2f, (start.y + end.y) / 2f)
            drawCircle(color = HazardCrimson, radius = 7f * zoomScale.coerceIn(0.8f, 1.5f), center = mid)
            drawCircle(color = Color.White, radius = 3.5f, center = mid)
        }
    }
}

/**
 * Natural water bodies & coastline styling for light theme
 */
private fun DrawScope.drawChennaiGeographyLight(
    width: Float,
    height: Float,
    project: (GeoPoint) -> Offset
) {
    // 1. Bay of Bengal with fresh sea blue
    val coastPath = Path().apply {
        moveTo(width * 0.91f, 0f)
        lineTo(width, 0f)
        lineTo(width, height)
        lineTo(width * 0.87f, height)
        lineTo(width * 0.86f, height * 0.65f)
        lineTo(width * 0.92f, height * 0.35f)
        close()
    }
    drawPath(coastPath, color = MapOceanLight)

    // Sandy Shoreline (Marina Beach)
    val beachPath = Path().apply {
        moveTo(width * 0.908f, 0f)
        lineTo(width * 0.918f, 0f)
        lineTo(width * 0.878f, height)
        lineTo(width * 0.868f, height)
        close()
    }
    drawPath(beachPath, color = MapBeachLight)

    // 2. Adyar River
    val pAdyar1 = project(GeoPoint(13.018, 80.195))
    val pAdyar2 = project(GeoPoint(13.015, 80.225))
    val pAdyar3 = project(GeoPoint(13.010, 80.255))
    val pAdyarCoast = project(GeoPoint(13.008, 80.275))

    val adyarPath = Path().apply {
        moveTo(pAdyar1.x, pAdyar1.y)
        quadraticTo(pAdyar2.x, pAdyar2.y, pAdyar3.x, pAdyar3.y)
        lineTo(pAdyarCoast.x, pAdyarCoast.y)
    }
    drawPath(
        adyarPath,
        color = MapRiverLight,
        style = Stroke(width = 7.0f, cap = StrokeCap.Round)
    )

    // 3. Cooum River
    val pCooum1 = project(GeoPoint(13.075, 80.215))
    val pCooum2 = project(GeoPoint(13.072, 80.245))
    val pCooumCoast = project(GeoPoint(13.068, 80.282))

    val cooumPath = Path().apply {
        moveTo(pCooum1.x, pCooum1.y)
        quadraticTo(pCooum2.x, pCooum2.y, pCooumCoast.x, pCooumCoast.y)
    }
    drawPath(
        cooumPath,
        color = MapRiverLight.copy(alpha = 0.85f),
        style = Stroke(width = 5.0f, cap = StrokeCap.Round)
    )

    // 4. Velachery Lake
    val pVelLake = project(GeoPoint(12.978, 80.218))
    drawCircle(
        color = MapRiverLight.copy(alpha = 0.6f),
        radius = 28f,
        center = pVelLake
    )
}

/**
 * Draw route path with smooth styling
 */
private fun DrawScope.drawRoutePath(
    nodeIds: List<String>,
    project: (GeoPoint) -> Offset,
    color: Color,
    strokeWidth: Float,
    isDashed: Boolean
) {
    if (nodeIds.size < 2) return

    val path = Path()
    var isFirst = true

    for (nodeId in nodeIds) {
        val node = ChennaiGraphData.NODE_MAP[nodeId] ?: continue
        val pt = project(node.point)
        if (isFirst) {
            path.moveTo(pt.x, pt.y)
            isFirst = false
        } else {
            path.lineTo(pt.x, pt.y)
        }
    }

    val style = if (isDashed) {
        Stroke(
            width = strokeWidth,
            cap = StrokeCap.Round,
            join = StrokeJoin.Round,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 8f), 0f)
        )
    } else {
        Stroke(
            width = strokeWidth,
            cap = StrokeCap.Round,
            join = StrokeJoin.Round
        )
    }

    drawPath(path, color = color, style = style)
}

/**
 * Transit nodes and Origin/Destination pins in light theme
 */
private fun DrawScope.drawTransitNodesLight(
    originNodeId: String,
    destNodeId: String,
    safeRouteNodeIds: List<String>,
    pulseAlpha: Float,
    zoomScale: Float,
    project: (GeoPoint) -> Offset
) {
    for (node in ChennaiGraphData.NODES) {
        val pos = project(node.point)
        val isOrigin = node.id == originNodeId
        val isDest = node.id == destNodeId
        val isInSafeRoute = safeRouteNodeIds.contains(node.id)

        when {
            isOrigin -> {
                // Vibrant Start Pin (Green)
                drawCircle(color = PrimaryGreen.copy(alpha = pulseAlpha * 0.35f), radius = 20f * zoomScale.coerceIn(0.9f, 1.5f), center = pos)
                drawCircle(color = PrimaryGreen, radius = 9f, center = pos)
                drawCircle(color = Color.White, radius = 4f, center = pos)
            }
            isDest -> {
                // Destination Pin (Black & Green)
                drawCircle(color = Color(0xFF111827).copy(alpha = pulseAlpha * 0.25f), radius = 20f * zoomScale.coerceIn(0.9f, 1.5f), center = pos)
                drawCircle(color = Color(0xFF111827), radius = 9f, center = pos)
                drawCircle(color = PrimaryGreen, radius = 4f, center = pos)
            }
            node.isHighGround -> {
                drawCircle(color = ElevatedPurple, radius = 5f, center = pos)
                drawCircle(color = Color.White, radius = 2f, center = pos)
            }
            isInSafeRoute -> {
                drawCircle(color = PrimaryGreen, radius = 4.5f, center = pos)
                drawCircle(color = Color.White, radius = 1.5f, center = pos)
            }
            else -> {
                drawCircle(color = Color(0xFF64748B), radius = 3.2f, center = pos)
            }
        }
    }
}

/**
 * Floating Minimalist Route Capsule (Clean white surface, dark text, green accents)
 */
@Composable
private fun FloatingRouteCapsule(
    originId: String,
    destId: String,
    isOffline: Boolean,
    onOriginClick: () -> Unit,
    onDestClick: () -> Unit,
    onSwap: () -> Unit,
    onToggleOffline: () -> Unit,
    modifier: Modifier = Modifier
) {
    val originName = ChennaiGraphData.NODE_MAP[originId]?.name ?: originId
    val destName = ChennaiGraphData.NODE_MAP[destId]?.name ?: destId

    Surface(
        color = SurfaceLight,
        shape = RoundedCornerShape(26.dp),
        shadowElevation = 4.dp,
        modifier = modifier
            .fillMaxWidth()
            .border(1.dp, SurfaceBorder, RoundedCornerShape(26.dp))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Origin Pill
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onOriginClick() }
                    .padding(vertical = 4.dp, horizontal = 4.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(PrimaryGreen)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = originName,
                    color = TextPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }

            // Arrow
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                tint = TextSecondary,
                modifier = Modifier.size(14.dp)
            )

            // Destination Pill
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onDestClick() }
                    .padding(vertical = 4.dp, horizontal = 4.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF111827))
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = destName,
                    color = TextPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1
                )
            }

            // Swap Button
            IconButton(
                onClick = onSwap,
                modifier = Modifier
                    .size(32.dp)
                    .testTag("swap_route_button")
            ) {
                Icon(
                    imageVector = Icons.Default.SwapHoriz,
                    contentDescription = "Swap Start and End",
                    tint = PrimaryGreen,
                    modifier = Modifier.size(20.dp)
                )
            }

            // Subtle divider
            Box(
                modifier = Modifier
                    .width(1.dp)
                    .height(18.dp)
                    .background(SurfaceBorder)
            )
            Spacer(modifier = Modifier.width(8.dp))

            // Connectivity Indicator (Minimalist Dot)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .clickable { onToggleOffline() }
                    .padding(horizontal = 6.dp, vertical = 4.dp)
                    .testTag("connectivity_status_badge")
            ) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (isOffline) WarningAmber else PrimaryGreen)
                )
                Spacer(modifier = Modifier.width(5.dp))
                Text(
                    text = if (isOffline) "OFFLINE" else "LIVE",
                    color = if (isOffline) WarningAmber else PrimaryGreenDark,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

/**
 * Minimalist Floating Icon Button in Light Theme
 */
@Composable
private fun MinimalIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    isActive: Boolean,
    onClick: () -> Unit
) {
    Surface(
        color = if (isActive) PrimaryGreenLight else SurfaceLight,
        shape = CircleShape,
        shadowElevation = 3.dp,
        modifier = Modifier
            .size(40.dp)
            .clickable { onClick() }
            .border(
                1.dp,
                if (isActive) PrimaryGreen else SurfaceBorder,
                CircleShape
            )
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = icon,
                contentDescription = contentDescription,
                tint = if (isActive) PrimaryGreenDark else TextPrimary,
                modifier = Modifier.size(19.dp)
            )
        }
    }
}

/**
 * Minimalist Expandable Legend Card in Light Theme
 */
@Composable
private fun MinimalistLegendCard(onClose: () -> Unit) {
    Surface(
        color = SurfaceLight,
        shape = RoundedCornerShape(16.dp),
        shadowElevation = 5.dp,
        modifier = Modifier
            .width(220.dp)
            .border(1.dp, SurfaceBorder, RoundedCornerShape(16.dp))
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = "Map Guide", color = TextPrimary, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Close Legend",
                    tint = TextSecondary,
                    modifier = Modifier
                        .size(16.dp)
                        .clickable { onClose() }
                )
            }
            Spacer(modifier = Modifier.height(10.dp))
            LegendRow(color = PrimaryGreen, label = "Safe Green Path", isDashed = false)
            LegendRow(color = NaiveRouteDanger, label = "Shortest (Flood Trap)", isDashed = true)
            LegendRow(color = PrimaryGreenDark, label = "Elevated Safe Road", isDashed = false)
            LegendRow(color = HazardCrimson, label = "Flooded / Blocked Road", isDashed = false)
            LegendRow(color = PrimaryGreen, label = "Key Landmarks", isDashed = false)
        }
    }
}

@Composable
private fun LegendRow(color: Color, label: String, isDashed: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(vertical = 4.dp)
    ) {
        Box(
            modifier = Modifier
                .width(16.dp)
                .height(4.dp)
                .background(color, shape = RoundedCornerShape(2.dp))
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(text = label, color = TextPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

/**
 * Minimalist Floating Route Bottom Summary in Light Theme
 */
@Composable
private fun MinimalFloatingRouteBar(
    safeRoute: RouteResult,
    naiveRoute: RouteResult,
    onViewExplanation: () -> Unit,
    modifier: Modifier = Modifier
) {
    val timeDiffMin = ((safeRoute.estimatedTimeSeconds - naiveRoute.estimatedTimeSeconds) / 60.0)
    val timeDiffStr = if (timeDiffMin >= 0) "+${(timeDiffMin * 10).toInt() / 10.0}m" else "${(timeDiffMin * 10).toInt() / 10.0}m"
    val safeMin = (safeRoute.estimatedTimeSeconds / 60.0).toInt()
    val safeKm = (safeRoute.totalDistanceMeters / 1000.0 * 10).toInt() / 10.0

    Card(
        colors = CardDefaults.cardColors(containerColor = SurfaceLight),
        shape = RoundedCornerShape(20.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 5.dp),
        modifier = modifier
            .fillMaxWidth()
            .border(1.dp, SurfaceBorder, RoundedCornerShape(20.dp))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Metrics
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "$safeMin min",
                        color = PrimaryGreenDark,
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "· $safeKm km",
                        color = TextPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "$timeDiffStr trade-off",
                        color = TextSecondary,
                        fontSize = 12.sp
                    )
                    if (naiveRoute.severeHazardsEncountered > 0) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "· ${naiveRoute.severeHazardsEncountered} subways avoided",
                            color = PrimaryGreen,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            // Clean action button to view rationale
            Surface(
                color = PrimaryGreenLight,
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .clickable { onViewExplanation() }
                    .border(1.dp, PrimaryGreen, RoundedCornerShape(12.dp))
                    .padding(horizontal = 14.dp, vertical = 8.dp)
                    .testTag("view_rationale_button")
            ) {
                Text(
                    text = "Why Safe? →",
                    color = PrimaryGreenDark,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

/**
 * Minimalist Node Tap Action Dialog in Light Theme
 */
@Composable
private fun MinimalNodeActionDialog(
    node: RoadNode,
    onSetOrigin: () -> Unit,
    onSetDest: () -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Card(
            colors = CardDefaults.cardColors(containerColor = SurfaceLight),
            shape = RoundedCornerShape(20.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
            modifier = Modifier
                .fillMaxWidth()
                .border(1.dp, SurfaceBorder, RoundedCornerShape(20.dp))
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = node.name,
                    color = TextPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Elevation: ${node.elevationMeters}m · Zone: ${node.areaZone}",
                    color = TextSecondary,
                    fontSize = 12.sp
                )
                Spacer(modifier = Modifier.height(18.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Surface(
                        color = PrimaryGreenLight,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { onSetOrigin() }
                            .border(1.dp, PrimaryGreen, RoundedCornerShape(12.dp))
                            .padding(vertical = 10.dp)
                    ) {
                        Text(
                            text = "Set Start",
                            color = PrimaryGreenDark,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }

                    Surface(
                        color = SurfaceCardAlt,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { onSetDest() }
                            .border(1.dp, Color(0xFF111827), RoundedCornerShape(12.dp))
                            .padding(vertical = 10.dp)
                    ) {
                        Text(
                            text = "Set Destination",
                            color = Color(0xFF111827),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }
                }
            }
        }
    }
}

/**
 * Minimalist Location Picker Dialog in Light Theme
 */
@Composable
private fun LocationPickerDialog(
    title: String,
    currentNodeId: String,
    otherNodeId: String,
    onSelectNode: (String) -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Card(
            colors = CardDefaults.cardColors(containerColor = SurfaceLight),
            shape = RoundedCornerShape(22.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
            modifier = Modifier
                .fillMaxWidth()
                .height(450.dp)
                .border(1.dp, SurfaceBorder, RoundedCornerShape(22.dp))
        ) {
            Column(modifier = Modifier.padding(18.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(text = title, color = TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    IconButton(onClick = onDismiss, modifier = Modifier.size(28.dp)) {
                        Icon(imageVector = Icons.Default.Close, contentDescription = "Close", tint = TextSecondary)
                    }
                }
                Spacer(modifier = Modifier.height(10.dp))

                LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(ChennaiGraphData.NODES) { node ->
                        val isSelected = node.id == currentNodeId
                        val isForbidden = node.id == otherNodeId

                        Surface(
                            color = when {
                                isSelected -> PrimaryGreenLight
                                isForbidden -> SurfaceCardAlt.copy(alpha = 0.5f)
                                else -> SurfaceLight
                            },
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .clickable(enabled = !isForbidden) { onSelectNode(node.id) }
                                .border(
                                    1.dp,
                                    if (isSelected) PrimaryGreen else SurfaceBorder,
                                    RoundedCornerShape(12.dp)
                                )
                                .padding(horizontal = 14.dp, vertical = 10.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column {
                                    Text(
                                        text = node.name,
                                        color = if (isForbidden) TextMuted else TextPrimary,
                                        fontSize = 13.sp,
                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium
                                    )
                                    Text(
                                        text = "${node.areaZone} · ${node.elevationMeters}m ground height",
                                        color = TextSecondary,
                                        fontSize = 11.sp
                                    )
                                }

                                if (node.isHighGround) {
                                    Surface(
                                        color = ElevatedPurple.copy(alpha = 0.12f),
                                        shape = RoundedCornerShape(6.dp)
                                    ) {
                                        Text(
                                            text = "Elevated Safe",
                                            color = ElevatedPurple,
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Bold,
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
