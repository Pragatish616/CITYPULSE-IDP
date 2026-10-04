package com.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AltRoute
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.SignalCellularAlt
import androidx.compose.material.icons.filled.SignalCellularConnectedNoInternet0Bar
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.ui.CityPulseUiState
import com.example.ui.CityPulseViewModel
import com.example.ui.screens.ExplanationView
import com.example.ui.screens.InteractiveMapView
import com.example.ui.screens.SimulationLabView
import com.example.ui.screens.WatchlistInspectorView
import com.example.ui.theme.AppBackground
import com.example.ui.theme.CyanPulse
import com.example.ui.theme.DeepNavyBackground
import com.example.ui.theme.HazardCrimson
import com.example.ui.theme.MyApplicationTheme
import com.example.ui.theme.PrimaryGreen
import com.example.ui.theme.PrimaryGreenDark
import com.example.ui.theme.PrimaryGreenLight
import com.example.ui.theme.SafeEmerald
import com.example.ui.theme.SurfaceBorder
import com.example.ui.theme.SurfaceCard
import com.example.ui.theme.SurfaceDarkNavy
import com.example.ui.theme.SurfaceLight
import com.example.ui.theme.TextMuted
import com.example.ui.theme.TextPrimary
import com.example.ui.theme.TextSecondary
import com.example.ui.theme.WarningAmber
import com.example.ui.theme.TextPrimary
import com.example.ui.theme.TextSecondary
import com.example.ui.theme.WarningAmber

class MainActivity : ComponentActivity() {

    private val viewModel: CityPulseViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MyApplicationTheme {
                val uiState by viewModel.uiState.collectAsStateWithLifecycle()
                CityPulseApp(
                    uiState = uiState,
                    viewModel = viewModel
                )
            }
        }
    }
}

data class NavTabItem(
    val title: String,
    val icon: ImageVector,
    val testTag: String
)

@Composable
fun CityPulseApp(
    uiState: CityPulseUiState,
    viewModel: CityPulseViewModel
) {
    val navItems = listOf(
        NavTabItem("Safe Map", Icons.Default.Map, "nav_tab_map"),
        NavTabItem("Why This Route?", Icons.Default.Psychology, "nav_tab_explanation"),
        NavTabItem("Flood Watch", Icons.Default.Shield, "nav_tab_watchlist"),
        NavTabItem("Rain Modes", Icons.Default.Tune, "nav_tab_sim_lab")
    )

    Scaffold(
        modifier = Modifier
            .fillMaxSize()
            .background(AppBackground),
        topBar = {
            if (uiState.selectedTab != 0) {
                MinimalTopAppBar(
                    selectedTab = uiState.selectedTab,
                    isOffline = uiState.isNetworkOfflineMode,
                    onToggleOffline = { viewModel.toggleOfflineMode() }
                )
            }
        },
        bottomBar = {
            NavigationBar(
                containerColor = SurfaceLight,
                tonalElevation = 3.dp,
                modifier = Modifier
                    .border(1.dp, SurfaceBorder)
                    .navigationBarsPadding()
            ) {
                navItems.forEachIndexed { index, item ->
                    val isSelected = uiState.selectedTab == index
                    NavigationBarItem(
                        selected = isSelected,
                        onClick = { viewModel.setSelectedTab(index) },
                        icon = {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = item.title,
                                tint = if (isSelected) PrimaryGreen else TextSecondary
                            )
                        },
                        label = {
                            Text(
                                text = item.title,
                                color = if (isSelected) PrimaryGreen else TextSecondary,
                                fontSize = 11.sp,
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium
                            )
                        },
                        colors = NavigationBarItemDefaults.colors(
                            indicatorColor = PrimaryGreenLight
                        ),
                        modifier = Modifier.testTag(item.testTag)
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    top = if (uiState.selectedTab == 0) 0.dp else innerPadding.calculateTopPadding(),
                    bottom = innerPadding.calculateBottomPadding()
                )
        ) {
            when (uiState.selectedTab) {
                0 -> InteractiveMapView(
                    originNodeId = uiState.originNodeId,
                    destNodeId = uiState.destNodeId,
                    edgeBeliefs = uiState.edgeBeliefs,
                    naiveRoute = uiState.naiveRoute,
                    cityPulseRoute = uiState.cityPulseRoute,
                    isOffline = uiState.isNetworkOfflineMode,
                    onSelectOrigin = { viewModel.setOrigin(it) },
                    onSelectDest = { viewModel.setDestination(it) },
                    onSwap = { viewModel.swapOriginDestination() },
                    onInspectEdge = { viewModel.inspectEdge(it) },
                    onToggleOffline = { viewModel.toggleOfflineMode() },
                    onNavigateToExplanation = { viewModel.setSelectedTab(1) }
                )

                1 -> ExplanationView(
                    decisionTrace = uiState.decisionTrace
                )

                2 -> WatchlistInspectorView(
                    edgeBeliefs = uiState.edgeBeliefs,
                    activeInspectedEdgeId = uiState.activeInspectedEdgeId,
                    observations = uiState.observations,
                    onSelectEdgeToInspect = { viewModel.inspectEdge(it) },
                    onSubmitReport = { edgeId, category, depthCm, desc ->
                        viewModel.submitHazardReport(edgeId, category, depthCm, desc)
                    }
                )

                3 -> SimulationLabView(
                    currentScenario = uiState.selectedScenario,
                    currentRiskProfile = uiState.riskProfile,
                    isOfflineMode = uiState.isNetworkOfflineMode,
                    onSelectScenario = { viewModel.setScenario(it) },
                    onSelectRiskProfile = { viewModel.setRiskProfile(it) },
                    onCustomZChanged = { viewModel.setCustomRiskZ(it) },
                    onToggleOfflineMode = { viewModel.toggleOfflineMode() },
                    onRecalculate = { viewModel.computeCurrentRouting() }
                )
            }
        }
    }
}

@Composable
private fun MinimalTopAppBar(
    selectedTab: Int,
    isOffline: Boolean,
    onToggleOffline: () -> Unit
) {
    val (title, subtitle) = when (selectedTab) {
        1 -> Pair("Why This Route?", "Clear explanations without jargon")
        2 -> Pair("Flood Watchlist", "Monitored low-lying areas across Chennai")
        3 -> Pair("Rain & Safety Modes", "Adjust caution level for heavy rainfall")
        else -> Pair("Safe Route", "Hazard-aware city routing")
    }

    Surface(
        color = SurfaceLight,
        shadowElevation = 2.dp,
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .border(1.dp, SurfaceBorder)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = title,
                    color = TextPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = subtitle,
                    color = TextSecondary,
                    fontSize = 12.sp
                )
            }

            // Connectivity Badge
            Surface(
                color = if (isOffline) WarningAmber.copy(alpha = 0.12f) else PrimaryGreenLight,
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier
                    .clickable { onToggleOffline() }
                    .border(
                        1.dp,
                        if (isOffline) WarningAmber else PrimaryGreen,
                        RoundedCornerShape(14.dp)
                    )
                    .padding(horizontal = 10.dp, vertical = 5.dp)
                    .testTag("connectivity_status_badge")
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(if (isOffline) WarningAmber else PrimaryGreen)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
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
}

