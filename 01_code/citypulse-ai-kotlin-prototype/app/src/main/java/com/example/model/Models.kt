package com.example.model

import kotlin.math.ln

/**
 * Geometric coordinates
 */
data class GeoPoint(
    val lat: Double,
    val lon: Double
)

/**
 * Road node in the Chennai urban network
 */
data class RoadNode(
    val id: String,
    val name: String,
    val point: GeoPoint,
    val elevationMeters: Double,
    val isHighGround: Boolean = false,
    val areaZone: String = "Chennai"
)

/**
 * Terrain prior category representing static physical risk (elevation, drainage, 2015/2023 flood history)
 */
enum class TerrainPriorType(val label: String, val priorL0: Double, val baseRiskDesc: String) {
    EXTREME_DEPRESSION("Extreme Flood Basin", 1.6, "Low elevation & historical 2015/2023 flood inundation zone"),
    HIGH_FLOOD_PRONE("High Waterlogging Prone", 0.85, "Chronic drainage choke point & river bank vicinity"),
    MODERATE_PRONE("Moderate Drainage Risk", -0.4, "Slow-draining urban corridor"),
    ELEVATED_RIDGE("Elevated High Ground", -2.2, "Flyover / elevated bypass / natural high ridge"),
    DEFAULT_URBAN("Standard Urban Road", -1.8, "Standard urban storm drainage capacity");

    /**
     * Prior probability p_0 = sigma(l_0)
     */
    val priorProbability: Double
        get() = 1.0 / (1.0 + Math.exp(-priorL0))
}

/**
 * Hazard classes with per-class temporal decay half-life T_c
 */
enum class HazardCategory(
    val displayName: String,
    val halfLifeMinutes: Long,
    val defaultAlpha: Double,
    val isSevereBlocking: Boolean
) {
    FLASH_FLOOD_SURGE("Flash Flooding", 45L, 0.92, true),
    CHRONIC_WATERLOGGING("Waterlogged Road", 240L, 0.85, false),
    SUBWAY_INUNDATION("Subway Inundation", 720L, 0.98, true),
    FALLEN_TREE_DEBRIS("Fallen Tree / Debris", 1440L, 0.90, false),
    ROAD_COLLAPSE("Road Breach / Damage", 2880L, 0.95, true);

    val halfLifeSeconds: Double
        get() = halfLifeMinutes * 60.0

    /**
     * Decay constant lambda = ln(2) / T_c
     */
    val decayRatePerSecond: Double
        get() = ln(2.0) / halfLifeSeconds
}

/**
 * Road Edge linking two nodes
 */
data class RoadEdge(
    val id: String,
    val fromNodeId: String,
    val toNodeId: String,
    val roadName: String,
    val lengthMeters: Double,
    val freeFlowSpeedKmh: Double,
    val terrainPrior: TerrainPriorType,
    val isSubwayOrUnderpass: Boolean = false,
    val isElevatedCorridor: Boolean = false
) {
    val freeFlowTimeSeconds: Double
        get() = (lengthMeters / (freeFlowSpeedKmh * (1000.0 / 3600.0)))
}

/**
 * Live or cached hazard observation
 */
data class HazardObservation(
    val id: String,
    val edgeId: String,
    val category: HazardCategory,
    val timestampEpochMs: Long,
    val sourceConfidenceAlpha: Double,
    val depthCm: Int = 0,
    val severityScore: Double = 0.7, // 0.0 to 1.0
    val reporterSource: String = "GCC Monsoon Watch",
    val description: String = ""
)

/**
 * Computed edge belief following log-odds fusion and pessimism under uncertainty
 */
data class EdgeBelief(
    val edgeId: String,
    val priorL0: Double,
    val fusedLiveDeltaL: Double,
    val fusedLogOdds: Double,
    val meanProbabilityPBar: Double,
    val effectiveObservationsN: Double,
    val pessimisticProbabilityPTilde: Double,
    val slowdownFactorDelta: Double,
    val computedEdgeCostSeconds: Double,
    val isSeveredByChanceConstraint: Boolean,
    val primaryHazardNotice: String? = null
)

/**
 * User class risk dial configuration
 */
data class RiskProfile(
    val profileName: String,
    val zDial: Double,
    val lambdaRiskAversionSeconds: Double,
    val description: String,
    val iconName: String
) {
    companion object {
        val COMMUTER = RiskProfile(
            profileName = "Commuter / Bike",
            zDial = 0.2,
            lambdaRiskAversionSeconds = 60.0,
            description = "Accepts moderate delay trade-offs; risk-neutral under ambiguity.",
            iconName = "two_wheeler"
        )
        val STANDARD_CAR = RiskProfile(
            profileName = "Standard Car",
            zDial = 1.0,
            lambdaRiskAversionSeconds = 180.0,
            description = "Balanced caution; actively avoids subways and high waterlogging.",
            iconName = "directions_car"
        )
        val EMERGENCY_AMBULANCE = RiskProfile(
            profileName = "Emergency / Ambulance",
            zDial = 2.0,
            lambdaRiskAversionSeconds = 420.0,
            description = "Pessimism under uncertainty; treats unverified hazards as dangerous.",
            iconName = "emergency"
        )

        val ALL_PROFILES = listOf(COMMUTER, STANDARD_CAR, EMERGENCY_AMBULANCE)
    }
}

/**
 * Detailed route calculation result
 */
data class RouteResult(
    val pathNodeIds: List<String>,
    val pathEdgeIds: List<String>,
    val totalDistanceMeters: Double,
    val estimatedTimeSeconds: Double,
    val freeFlowBaseTimeSeconds: Double,
    val avgHazardExposurePct: Double,
    val severeHazardsEncountered: Int,
    val elevatedRidgeDistanceMeters: Double,
    val isSuccess: Boolean = true,
    val failureReason: String? = null
)

/**
 * Trace comparing Naive Shortest route vs CityPulse Hazard-Aware route
 */
data class DecisionFactSet(
    val timeDiffMinutes: Double,
    val distanceDiffKm: Double,
    val hazardReductionPct: Double,
    val naiveHazardPct: Double,
    val safeHazardPct: Double,
    val avoidedChokepoints: List<String>,
    val highGroundDetourKm: Double,
    val pessimismZValue: Double,
    val networkMode: String,
    val confidenceBadgePct: Int
)

data class DecisionTrace(
    val timestampMs: Long,
    val originNodeName: String,
    val destinationNodeName: String,
    val naiveRoute: RouteResult,
    val cityPulseRoute: RouteResult,
    val facts: DecisionFactSet,
    val tier0Rationale: String,
    val tier1Briefing: String,
    val isSymbolicallyVerified: Boolean,
    val verificationDetails: List<String>
)

/**
 * Building classification for Chennai urban cartography
 */
enum class BuildingType {
    HERITAGE_LANDMARK,
    COMMERCIAL_TOWER,
    TECH_PARK,
    INSTITUTIONAL,
    TRANSIT_HUB,
    URBAN_RESIDENTIAL
}

/**
 * Architectural Building Footprint on the Chennai Map
 */
data class MapBuilding(
    val id: String,
    val name: String,
    val center: GeoPoint,
    val widthKm: Double,
    val heightKm: Double,
    val heightStories: Int,
    val type: BuildingType,
    val isProminentLandmark: Boolean = false,
    val rotationDeg: Float = 0f
)

