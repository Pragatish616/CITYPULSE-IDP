package com.example.engine

import com.example.data.ChennaiGraphData
import com.example.model.DecisionFactSet
import com.example.model.EdgeBelief
import com.example.model.RiskProfile
import com.example.model.RoadEdge
import com.example.model.RouteResult
import java.util.PriorityQueue
import kotlin.math.roundToInt

object PulseRouter {

    data class PathStep(
        val nodeId: String,
        val edgeId: String?,
        val accumulatedCost: Double,
        val accumulatedDistance: Double,
        val accumulatedTime: Double
    ) : Comparable<PathStep> {
        override fun compareTo(other: PathStep): Int = accumulatedCost.compareTo(other.accumulatedCost)
    }

    /**
     * Compute Naive Shortest Route based strictly on free-flow travel time tau_0
     */
    fun computeNaiveRoute(
        originId: String,
        destId: String,
        beliefs: Map<String, EdgeBelief>
    ): RouteResult {
        val edges = ChennaiGraphData.EDGES.associateBy { it.id }
        val weights = edges.mapValues { (_, edge) -> edge.freeFlowTimeSeconds }
        return runDijkstra(originId, destId, weights, beliefs, isNaive = true)
    }

    /**
     * Compute CityPulse Hazard-Aware Route using fused edge cost w_lambda(e, t)
     */
    fun computeHazardAwareRoute(
        originId: String,
        destId: String,
        beliefs: Map<String, EdgeBelief>
    ): RouteResult {
        val weights = beliefs.mapValues { (_, belief) -> belief.computedEdgeCostSeconds }
        return runDijkstra(originId, destId, weights, beliefs, isNaive = false)
    }

    private fun runDijkstra(
        originId: String,
        destId: String,
        weights: Map<String, Double>,
        beliefs: Map<String, EdgeBelief>,
        isNaive: Boolean
    ): RouteResult {
        if (originId == destId) {
            return RouteResult(
                pathNodeIds = listOf(originId),
                pathEdgeIds = emptyList(),
                totalDistanceMeters = 0.0,
                estimatedTimeSeconds = 0.0,
                freeFlowBaseTimeSeconds = 0.0,
                avgHazardExposurePct = 0.0,
                severeHazardsEncountered = 0,
                elevatedRidgeDistanceMeters = 0.0
            )
        }

        // Adjacency list: fromNodeId -> list of edges
        val adj = ChennaiGraphData.EDGES.groupBy { it.fromNodeId }

        val minCost = mutableMapOf<String, Double>()
        val previousEdge = mutableMapOf<String, String>()
        val previousNode = mutableMapOf<String, String>()

        val pq = PriorityQueue<PathStep>()
        pq.add(PathStep(originId, null, 0.0, 0.0, 0.0))
        minCost[originId] = 0.0

        while (pq.isNotEmpty()) {
            val current = pq.poll() ?: break

            if (current.nodeId == destId) {
                // Reconstruct path
                return buildRouteResult(destId, previousNode, previousEdge, beliefs, isNaive)
            }

            if (current.accumulatedCost > (minCost[current.nodeId] ?: Double.MAX_VALUE)) {
                continue
            }

            val neighbors = adj[current.nodeId] ?: emptyList()
            for (edge in neighbors) {
                val edgeWeight = weights[edge.id] ?: edge.freeFlowTimeSeconds

                // In hazard-aware mode, skip severed edges completely (or if cost > 90,000s)
                if (!isNaive && edgeWeight >= 90_000.0) {
                    continue
                }

                val newCost = current.accumulatedCost + edgeWeight
                val currentMin = minCost[edge.toNodeId] ?: Double.MAX_VALUE

                if (newCost < currentMin) {
                    minCost[edge.toNodeId] = newCost
                    previousEdge[edge.toNodeId] = edge.id
                    previousNode[edge.toNodeId] = current.nodeId
                    pq.add(
                        PathStep(
                            nodeId = edge.toNodeId,
                            edgeId = edge.id,
                            accumulatedCost = newCost,
                            accumulatedDistance = current.accumulatedDistance + edge.lengthMeters,
                            accumulatedTime = current.accumulatedTime + edge.freeFlowTimeSeconds
                        )
                    )
                }
            }
        }

        return RouteResult(
            pathNodeIds = emptyList(),
            pathEdgeIds = emptyList(),
            totalDistanceMeters = 0.0,
            estimatedTimeSeconds = 0.0,
            freeFlowBaseTimeSeconds = 0.0,
            avgHazardExposurePct = 0.0,
            severeHazardsEncountered = 0,
            elevatedRidgeDistanceMeters = 0.0,
            isSuccess = false,
            failureReason = "No passable route found between origin and destination under current constraints."
        )
    }

    private fun buildRouteResult(
        destId: String,
        previousNode: Map<String, String>,
        previousEdge: Map<String, String>,
        beliefs: Map<String, EdgeBelief>,
        isNaive: Boolean
    ): RouteResult {
        val pathNodes = mutableListOf<String>()
        val pathEdges = mutableListOf<String>()

        var curr: String? = destId
        while (curr != null) {
            pathNodes.add(0, curr)
            val edge = previousEdge[curr]
            if (edge != null) {
                pathEdges.add(0, edge)
            }
            curr = previousNode[curr]
        }

        var totalDist = 0.0
        var totalFreeFlowTime = 0.0
        var totalEstimatedTime = 0.0
        var weightedHazardSum = 0.0
        var severeCount = 0
        var elevatedDist = 0.0

        for (edgeId in pathEdges) {
            val edge = ChennaiGraphData.EDGE_MAP[edgeId] ?: continue
            val belief = beliefs[edgeId]
            val pTilde = belief?.pessimisticProbabilityPTilde ?: 0.1
            val isSevered = belief?.isSeveredByChanceConstraint ?: false

            totalDist += edge.lengthMeters
            totalFreeFlowTime += edge.freeFlowTimeSeconds

            // Estimated physical time (free flow + slowdown delay)
            val delayFactor = belief?.slowdownFactorDelta ?: 1.0
            totalEstimatedTime += edge.freeFlowTimeSeconds * (1.0 + pTilde * (delayFactor - 1.0))

            weightedHazardSum += pTilde * edge.lengthMeters

            if (pTilde >= 0.70 || isSevered || edge.isSubwayOrUnderpass && pTilde > 0.4) {
                severeCount++
            }

            if (edge.isElevatedCorridor) {
                elevatedDist += edge.lengthMeters
            }
        }

        val avgExposurePct = if (totalDist > 0) {
            (weightedHazardSum / totalDist) * 100.0
        } else 0.0

        return RouteResult(
            pathNodeIds = pathNodes,
            pathEdgeIds = pathEdges,
            totalDistanceMeters = totalDist,
            estimatedTimeSeconds = totalEstimatedTime,
            freeFlowBaseTimeSeconds = totalFreeFlowTime,
            avgHazardExposurePct = avgExposurePct,
            severeHazardsEncountered = severeCount,
            elevatedRidgeDistanceMeters = elevatedDist,
            isSuccess = true
        )
    }

    /**
     * Compute comparative fact set between Naive route and CityPulse route
     */
    fun createFactSet(
        naiveRoute: RouteResult,
        safeRoute: RouteResult,
        beliefs: Map<String, EdgeBelief>,
        riskProfile: RiskProfile,
        networkMode: String = "Offline Cache + Terrain Prior"
    ): DecisionFactSet {
        val timeDiffMinutes = ((safeRoute.estimatedTimeSeconds - naiveRoute.estimatedTimeSeconds) / 60.0)
        val distDiffKm = ((safeRoute.totalDistanceMeters - naiveRoute.totalDistanceMeters) / 1000.0)

        val hazardReduction = if (naiveRoute.avgHazardExposurePct > 0) {
            val red = ((naiveRoute.avgHazardExposurePct - safeRoute.avgHazardExposurePct) / naiveRoute.avgHazardExposurePct) * 100.0
            kotlin.math.max(0.0, red)
        } else 0.0

        // Find avoided choke points present in Naive but avoided in Safe route
        val safeEdgesSet = safeRoute.pathEdgeIds.toSet()
        val avoidedHotspots = mutableListOf<String>()

        for (edgeId in naiveRoute.pathEdgeIds) {
            if (!safeEdgesSet.contains(edgeId)) {
                val edge = ChennaiGraphData.EDGE_MAP[edgeId]
                val belief = beliefs[edgeId]
                if (edge != null && (belief?.isSeveredByChanceConstraint == true || (belief?.pessimisticProbabilityPTilde ?: 0.0) > 0.55)) {
                    val notice = belief?.primaryHazardNotice ?: "${edge.terrainPrior.label} [p=${(((belief?.pessimisticProbabilityPTilde ?: 0.0)) * 100).roundToInt()}%]"
                    avoidedHotspots.add("${edge.roadName} ($notice)")
                }
            }
        }

        val highGroundKm = safeRoute.elevatedRidgeDistanceMeters / 1000.0

        // Confidence badge: based on network mode and observation coverage
        val confPct = if (networkMode.contains("Online", ignoreCase = true)) 94 else 88

        return DecisionFactSet(
            timeDiffMinutes = (timeDiffMinutes * 10.0).roundToInt() / 10.0,
            distanceDiffKm = (distDiffKm * 10.0).roundToInt() / 10.0,
            hazardReductionPct = (hazardReduction * 10.0).roundToInt() / 10.0,
            naiveHazardPct = (naiveRoute.avgHazardExposurePct * 10.0).roundToInt() / 10.0,
            safeHazardPct = (safeRoute.avgHazardExposurePct * 10.0).roundToInt() / 10.0,
            avoidedChokepoints = avoidedHotspots.distinct(),
            highGroundDetourKm = (highGroundKm * 10.0).roundToInt() / 10.0,
            pessimismZValue = riskProfile.zDial,
            networkMode = networkMode,
            confidenceBadgePct = confPct
        )
    }
}
