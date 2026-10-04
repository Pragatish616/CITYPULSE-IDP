package com.example.engine

import com.example.data.ChennaiGraphData
import com.example.model.EdgeBelief
import com.example.model.HazardObservation
import com.example.model.RiskProfile
import com.example.model.RoadEdge
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Implements CityPulse Hazard Belief log-odds fusion with per-class temporal decay
 * and pessimism-under-uncertainty edge weighting (ADR-002, ADR-003).
 */
object BeliefFusionEngine {

    /**
     * Compute EdgeBelief for all edges at a given point in time
     */
    fun computeEdgeBeliefs(
        edges: List<RoadEdge> = ChennaiGraphData.EDGES,
        observations: List<HazardObservation>,
        currentTimeMs: Long = System.currentTimeMillis(),
        riskProfile: RiskProfile = RiskProfile.STANDARD_CAR,
        isNetworkOnline: Boolean = true
    ): Map<String, EdgeBelief> {
        // Group observations by target edge
        val obsByEdge = observations.groupBy { it.edgeId }

        return edges.associate { edge ->
            val edgeObs = obsByEdge[edge.id] ?: emptyList()
            val belief = computeSingleEdgeBelief(
                edge = edge,
                observations = edgeObs,
                currentTimeMs = currentTimeMs,
                riskProfile = riskProfile,
                isNetworkOnline = isNetworkOnline
            )
            edge.id to belief
        }
    }

    /**
     * Single edge log-odds fusion and pessimistic evaluation
     */
    fun computeSingleEdgeBelief(
        edge: RoadEdge,
        observations: List<HazardObservation>,
        currentTimeMs: Long,
        riskProfile: RiskProfile,
        isNetworkOnline: Boolean
    ): EdgeBelief {
        val l0 = edge.terrainPrior.priorL0
        var deltaLSum = 0.0
        var nEffSum = 0.0
        var primaryNotice: String? = null
        var maxDepthCm = 0

        for (obs in observations) {
            val ageSeconds = max(0.0, (currentTimeMs - obs.timestampEpochMs) / 1000.0)
            val halfLifeSec = obs.category.halfLifeSeconds
            val decay = exp(-ln(2.0) * (ageSeconds / halfLifeSec))

            // logit(alpha) = ln(alpha / (1 - alpha))
            val alphaClamped = min(0.999, max(0.001, obs.sourceConfidenceAlpha))
            val logitAlpha = ln(alphaClamped / (1.0 - alphaClamped))

            val observationWeight = decay * logitAlpha * obs.severityScore
            deltaLSum += observationWeight
            nEffSum += decay

            if (obs.depthCm > maxDepthCm) {
                maxDepthCm = obs.depthCm
            }

            if (primaryNotice == null || obs.category.isSevereBlocking) {
                val ageMin = (ageSeconds / 60.0).toInt()
                primaryNotice = "${obs.category.displayName} (${obs.depthCm}cm, rep ${ageMin}m ago, ${((decay * obs.sourceConfidenceAlpha) * 100).toInt()}% conf)"
            }
        }

        // Fused log-odds: l(e, t) = l_0(e) + sum delta_l
        val fusedLogOdds = l0 + deltaLSum

        // Mean probability: p_bar = sigma(l)
        val pBar = 1.0 / (1.0 + exp(-fusedLogOdds))

        // Pessimism under uncertainty:
        // n_0 = 3.0 (prior pseudo-observations corresponding to static terrain baseline)
        val n0 = 3.0
        val varianceTerm = sqrt((pBar * (1.0 - pBar)) / (nEffSum + n0))
        val pTilde = min(0.99, max(0.01, pBar + riskProfile.zDial * varianceTerm))

        // Depth-disruption slowdown from Pregnolato et al. (2017):
        // delta(p) = 1.0 + 3.2 * (p_tilde)^1.5
        val deltaSlowdown = 1.0 + 3.2 * pTilde.pow(1.5)

        // Severity multiplier: Subways have higher consequence if flooded
        val severityMultiplier = if (edge.isSubwayOrUnderpass) 2.2 else 1.0

        // Chance constraint check:
        // Subways are severed if depth >= 35cm or high belief of inundation.
        // Surface roads are severed if live depth >= 60cm or confirmed impassable breach.
        val isChanceConstraintSevered = (edge.isSubwayOrUnderpass && maxDepthCm >= 35) ||
                (edge.isSubwayOrUnderpass && pTilde >= 0.85) ||
                (deltaLSum > 0.0 && pTilde >= 0.92) ||
                (maxDepthCm >= 60)

        // w_lambda(e, t) = tau_0 * [1 + p_tilde * (delta - 1)] + lambda * p_tilde * s * tau_0
        val tau0 = edge.freeFlowTimeSeconds
        val computedCostSeconds = if (isChanceConstraintSevered) {
            100_000.0 // Severed edge
        } else {
            val travelDelayTerm = tau0 * (1.0 + pTilde * (deltaSlowdown - 1.0))
            val riskPenaltyTerm = riskProfile.lambdaRiskAversionSeconds * pTilde * severityMultiplier * (tau0 / 60.0)
            travelDelayTerm + riskPenaltyTerm
        }

        return EdgeBelief(
            edgeId = edge.id,
            priorL0 = l0,
            fusedLiveDeltaL = deltaLSum,
            fusedLogOdds = fusedLogOdds,
            meanProbabilityPBar = pBar,
            effectiveObservationsN = nEffSum,
            pessimisticProbabilityPTilde = pTilde,
            slowdownFactorDelta = deltaSlowdown,
            computedEdgeCostSeconds = computedCostSeconds,
            isSeveredByChanceConstraint = isChanceConstraintSevered,
            primaryHazardNotice = primaryNotice
        )
    }
}
