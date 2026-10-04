package com.example.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.ChennaiGraphData
import com.example.data.HazardRepository
import com.example.data.SimulationScenario
import com.example.data.local.AppDatabase
import com.example.engine.BeliefFusionEngine
import com.example.engine.PulseRouter
import com.example.engine.SymbolicExplanationEngine
import com.example.model.DecisionTrace
import com.example.model.EdgeBelief
import com.example.model.HazardCategory
import com.example.model.HazardObservation
import com.example.model.RiskProfile
import com.example.model.RouteResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

data class CityPulseUiState(
    val originNodeId: String = "node_saidapet",
    val destNodeId: String = "node_madipakkam",
    val selectedScenario: SimulationScenario = SimulationScenario.MONSOON_TORRENTIAL_SURGE,
    val riskProfile: RiskProfile = RiskProfile.STANDARD_CAR,
    val isNetworkOfflineMode: Boolean = true, // Default offline-first as per paper mandate!
    val edgeBeliefs: Map<String, EdgeBelief> = emptyMap(),
    val naiveRoute: RouteResult? = null,
    val cityPulseRoute: RouteResult? = null,
    val decisionTrace: DecisionTrace? = null,
    val observations: List<HazardObservation> = emptyList(),
    val selectedTab: Int = 0,
    val activeInspectedEdgeId: String? = "e_vel_bypass_vj_fwd",
    val isRecalculating: Boolean = false
)

class CityPulseViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getDatabase(application)
    private val repository = HazardRepository(db.hazardDao())

    private val _uiState = MutableStateFlow(CityPulseUiState())
    val uiState: StateFlow<CityPulseUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            repository.seedDefaultWatchlist()
            repository.applyScenario(SimulationScenario.MONSOON_TORRENTIAL_SURGE)
            repository.allObservationsFlow.collect { obsList ->
                _uiState.update { it.copy(observations = obsList) }
                computeCurrentRouting()
            }
        }
    }

    fun setOrigin(id: String) {
        if (id != _uiState.value.destNodeId) {
            _uiState.update { it.copy(originNodeId = id) }
            computeCurrentRouting()
        }
    }

    fun setDestination(id: String) {
        if (id != _uiState.value.originNodeId) {
            _uiState.update { it.copy(destNodeId = id) }
            computeCurrentRouting()
        }
    }

    fun swapOriginDestination() {
        _uiState.update { current ->
            current.copy(
                originNodeId = current.destNodeId,
                destNodeId = current.originNodeId
            )
        }
        computeCurrentRouting()
    }

    fun setRiskProfile(profile: RiskProfile) {
        _uiState.update { it.copy(riskProfile = profile) }
        computeCurrentRouting()
    }

    fun setCustomRiskZ(zValue: Double) {
        val customProfile = RiskProfile(
            profileName = "Custom (z=${(zValue * 10).toInt() / 10.0})",
            zDial = zValue,
            lambdaRiskAversionSeconds = 60.0 + (zValue * 160.0),
            description = "Custom tuned risk dial with calibrated pessimism.",
            iconName = "tune"
        )
        _uiState.update { it.copy(riskProfile = customProfile) }
        computeCurrentRouting()
    }

    fun setScenario(scenario: SimulationScenario) {
        viewModelScope.launch {
            _uiState.update { it.copy(selectedScenario = scenario) }
            repository.applyScenario(scenario)
        }
    }

    fun toggleOfflineMode() {
        _uiState.update { it.copy(isNetworkOfflineMode = !it.isNetworkOfflineMode) }
        computeCurrentRouting()
    }

    fun setSelectedTab(tab: Int) {
        _uiState.update { it.copy(selectedTab = tab) }
    }

    fun inspectEdge(edgeId: String?) {
        _uiState.update { it.copy(activeInspectedEdgeId = edgeId) }
    }

    fun submitHazardReport(
        edgeId: String,
        category: HazardCategory,
        depthCm: Int,
        description: String
    ) {
        viewModelScope.launch {
            val observation = HazardObservation(
                id = UUID.randomUUID().toString(),
                edgeId = edgeId,
                category = category,
                timestampEpochMs = System.currentTimeMillis(),
                sourceConfidenceAlpha = 0.90,
                depthCm = depthCm,
                severityScore = if (depthCm > 40) 1.0 else 0.7,
                reporterSource = "On-Device Reporter",
                description = description
            )
            repository.insertObservation(observation)
        }
    }

    fun computeCurrentRouting() {
        val state = _uiState.value
        val now = System.currentTimeMillis()

        // 1. Belief log-odds fusion with per-class decay & pessimism
        val beliefs = BeliefFusionEngine.computeEdgeBeliefs(
            edges = ChennaiGraphData.EDGES,
            observations = state.observations,
            currentTimeMs = now,
            riskProfile = state.riskProfile,
            isNetworkOnline = !state.isNetworkOfflineMode
        )

        // 2. Dual route computation
        val naiveRoute = PulseRouter.computeNaiveRoute(
            originId = state.originNodeId,
            destId = state.destNodeId,
            beliefs = beliefs
        )

        val safeRoute = PulseRouter.computeHazardAwareRoute(
            originId = state.originNodeId,
            destId = state.destNodeId,
            beliefs = beliefs
        )

        // 3. Decision Trace & Fact Set
        val networkModeLabel = if (state.isNetworkOfflineMode) {
            "Zero-Connectivity (On-Device Graph + Terrain Prior l0)"
        } else {
            "Live-Enriched (Server Stream + Local Prior)"
        }

        val facts = PulseRouter.createFactSet(
            naiveRoute = naiveRoute,
            safeRoute = safeRoute,
            beliefs = beliefs,
            riskProfile = state.riskProfile,
            networkMode = networkModeLabel
        )

        val originNode = ChennaiGraphData.NODE_MAP[state.originNodeId]?.name ?: state.originNodeId
        val destNode = ChennaiGraphData.NODE_MAP[state.destNodeId]?.name ?: state.destNodeId

        // 4. Tier 0 and Tier 1 generation + Symbolic Fact Verification
        val tier0Rationale = SymbolicExplanationEngine.generateTier0Rationale(facts, originNode, destNode)
        val candidateTier1 = SymbolicExplanationEngine.generateTier1Briefing(facts, originNode, destNode)
        val verification = SymbolicExplanationEngine.verifyExplanation(candidateTier1, facts, tier0Rationale)

        val decisionTrace = DecisionTrace(
            timestampMs = now,
            originNodeName = originNode,
            destinationNodeName = destNode,
            naiveRoute = naiveRoute,
            cityPulseRoute = safeRoute,
            facts = facts,
            tier0Rationale = tier0Rationale,
            tier1Briefing = verification.approvedText,
            isSymbolicallyVerified = verification.isVerified,
            verificationDetails = if (verification.isVerified) verification.verifiedFacts else verification.flaggedDiscrepancies
        )

        _uiState.update { current ->
            current.copy(
                edgeBeliefs = beliefs,
                naiveRoute = naiveRoute,
                cityPulseRoute = safeRoute,
                decisionTrace = decisionTrace
            )
        }
    }
}
