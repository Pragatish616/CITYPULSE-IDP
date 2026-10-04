package com.example

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.data.ChennaiGraphData
import com.example.engine.BeliefFusionEngine
import com.example.engine.PulseRouter
import com.example.engine.SymbolicExplanationEngine
import com.example.model.DecisionFactSet
import com.example.model.HazardCategory
import com.example.model.HazardObservation
import com.example.model.RiskProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class ExampleRobolectricTest {

    @Test
    fun `read string from context`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val appName = context.getString(R.string.app_name)
        assertEquals("CityPulse AI", appName)
    }

    @Test
    fun `test belief fusion log-odds and pessimism calculation`() {
        val edge = ChennaiGraphData.EDGES.first { it.id == "e_vyas_subway_fwd" }
        val now = System.currentTimeMillis()

        // Test with single severe observation
        val observation = HazardObservation(
            id = "test-1",
            edgeId = edge.id,
            category = HazardCategory.SUBWAY_INUNDATION,
            timestampEpochMs = now,
            sourceConfidenceAlpha = 0.95,
            depthCm = 60,
            severityScore = 1.0,
            reporterSource = "Test Police",
            description = "Submerged subway"
        )

        val belief = BeliefFusionEngine.computeSingleEdgeBelief(
            edge = edge,
            observations = listOf(observation),
            currentTimeMs = now,
            riskProfile = RiskProfile.STANDARD_CAR,
            isNetworkOnline = false
        )

        assertTrue("Pessimistic probability should be high for flooded subway", belief.pessimisticProbabilityPTilde > 0.8)
        assertTrue("Subway with 60cm depth should be severed", belief.isSeveredByChanceConstraint)
    }

    @Test
    fun `test pulse router avoids flooded subways`() {
        val beliefs = BeliefFusionEngine.computeEdgeBeliefs(
            edges = ChennaiGraphData.EDGES,
            observations = listOf(
                HazardObservation(
                    id = "obs-vyas",
                    edgeId = "e_vyas_subway_fwd",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = System.currentTimeMillis(),
                    sourceConfidenceAlpha = 0.99,
                    depthCm = 70,
                    severityScore = 1.0,
                    reporterSource = "Control Room",
                    description = "Closed"
                )
            ),
            currentTimeMs = System.currentTimeMillis(),
            riskProfile = RiskProfile.STANDARD_CAR,
            isNetworkOnline = true
        )

        val naiveRoute = PulseRouter.computeNaiveRoute("node_central", "node_perambur", beliefs)
        val safeRoute = PulseRouter.computeHazardAwareRoute("node_central", "node_perambur", beliefs)

        assertTrue(naiveRoute.isSuccess)
        assertTrue(safeRoute.isSuccess)
        // The safe route should not use the severed subway edge
        assertFalse(safeRoute.pathEdgeIds.contains("e_vyas_subway_fwd"))
    }

    @Test
    fun `test symbolic explanation engine verifies numbers and fails closed on hallucination`() {
        val facts = DecisionFactSet(
            timeDiffMinutes = 4.2,
            distanceDiffKm = 1.8,
            hazardReductionPct = 78.0,
            naiveHazardPct = 85.0,
            safeHazardPct = 7.0,
            avoidedChokepoints = listOf("Vyasarpadi Subway"),
            highGroundDetourKm = 3.5,
            pessimismZValue = 1.0,
            networkMode = "Offline Mode",
            confidenceBadgePct = 88
        )

        val tier0 = SymbolicExplanationEngine.generateTier0Rationale(facts, "Central", "Vyasarpadi")
        assertNotNull(tier0)

        // Grounded candidate text: contains valid numbers 78.0%, +4.2, +1.8, 3.5
        val validCandidate = "Rerouted to achieve 78.0% hazard reduction with +4.2 min and +1.8 km distance via 3.5 km elevated corridor."
        val validResult = SymbolicExplanationEngine.verifyExplanation(validCandidate, facts, tier0)
        assertTrue(validResult.isVerified)

        // Hallucinated text with invented numbers (e.g. 99.9% or 45 min)
        val hallucinatedCandidate = "Rerouted with 99.9% confidence saving 45 minutes of transit time."
        val hallucinatedResult = SymbolicExplanationEngine.verifyExplanation(hallucinatedCandidate, facts, tier0)
        assertFalse("Hallucination must fail closed", hallucinatedResult.isVerified)
        assertEquals(tier0, hallucinatedResult.approvedText)
    }
}
