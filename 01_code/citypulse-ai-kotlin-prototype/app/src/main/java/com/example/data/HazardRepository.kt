package com.example.data

import com.example.data.local.HazardDao
import com.example.data.local.HazardEntity
import com.example.model.HazardCategory
import com.example.model.HazardObservation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.UUID

enum class SimulationScenario(val title: String, val subtitle: String, val icon: String) {
    MONSOON_TORRENTIAL_SURGE("Monsoon Downpour Surge", "Velachery lake overflow & subways flooded", "thunderstorm"),
    SUBWAY_CLOSURES_SPATE("Subway Inundation Spate", "North & Central Chennai subways closed", "tunnel"),
    CYCLONE_MICHAUNG_REPLAY("Cyclone Michaung Replay", "Catastrophic low-basin inundation", "cyclone"),
    DRY_WEATHER_BASELINE("Dry Baseline (Terrain Prior)", "Pure static hazard prior l0 without live signal", "wb_sunny")
}

class HazardRepository(private val hazardDao: HazardDao) {

    val allObservationsFlow: Flow<List<HazardObservation>> = hazardDao.getAllHazardsFlow()
        .map { entities -> entities.map { it.toDomain() } }

    val watchlistFlow: Flow<List<HazardEntity>> = hazardDao.getWatchlistFlow()

    suspend fun seedDefaultWatchlist() {
        val now = System.currentTimeMillis()
        val defaultList = ChennaiGraphData.CHENNAI_WATCHLIST.map { spot ->
            HazardEntity(
                id = spot.id,
                edgeId = spot.edgeId,
                categoryName = HazardCategory.CHRONIC_WATERLOGGING.name,
                timestampEpochMs = now - (30 * 60 * 1000), // 30m ago
                sourceConfidenceAlpha = 0.90,
                depthCm = 20,
                severityScore = 0.75,
                reporterSource = "GCC Chronic Waterlogging Registry",
                description = spot.floodVulnerabilityNote,
                isChronicWatchlist = true,
                locationTitle = spot.title
            )
        }
        hazardDao.insertHazards(defaultList)
    }

    suspend fun applyScenario(scenario: SimulationScenario) {
        hazardDao.clearLiveHazards()
        val now = System.currentTimeMillis()

        val observations = when (scenario) {
            SimulationScenario.MONSOON_TORRENTIAL_SURGE -> listOf(
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vyas_subway_fwd",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = now - (15 * 60 * 1000), // 15 mins ago
                    sourceConfidenceAlpha = 0.98,
                    depthCm = 70,
                    severityScore = 1.0,
                    reporterSource = "Chennai Traffic Police / GCC",
                    description = "Vyasarpadi Ganesapuram Subway completely submerged. Water depth 70cm, pumps failing."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vyas_subway_rev",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = now - (15 * 60 * 1000),
                    sourceConfidenceAlpha = 0.98,
                    depthCm = 70,
                    severityScore = 1.0,
                    reporterSource = "Chennai Traffic Police / GCC",
                    description = "Subway submerged both directions."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vel_bypass_vj_fwd",
                    category = HazardCategory.FLASH_FLOOD_SURGE,
                    timestampEpochMs = now - (25 * 60 * 1000), // 25 mins ago
                    sourceConfidenceAlpha = 0.94,
                    depthCm = 55,
                    severityScore = 0.90,
                    reporterSource = "Ward 178 Volunteer Watch",
                    description = "Velachery Lake surplus channel breach. Water across entire 100ft bypass."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vel_bypass_vj_rev",
                    category = HazardCategory.FLASH_FLOOD_SURGE,
                    timestampEpochMs = now - (25 * 60 * 1000),
                    sourceConfidenceAlpha = 0.94,
                    depthCm = 55,
                    severityScore = 0.90,
                    reporterSource = "Ward 178 Volunteer Watch",
                    description = "Lake breach affecting both directions."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vel_vj_madi_fwd",
                    category = HazardCategory.CHRONIC_WATERLOGGING,
                    timestampEpochMs = now - (40 * 60 * 1000),
                    sourceConfidenceAlpha = 0.88,
                    depthCm = 45,
                    severityScore = 0.85,
                    reporterSource = "Citizen Hazard Ingest",
                    description = "Madipakkam Lake road deep waterlogging up to knee height."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_panagal_usman_fwd",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = now - (35 * 60 * 1000),
                    sourceConfidenceAlpha = 0.92,
                    depthCm = 50,
                    severityScore = 0.95,
                    reporterSource = "GCC Stormwater Monitoring",
                    description = "South Usman Road subway flooded; barricades deployed."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_tidel_perungudi_fwd",
                    category = HazardCategory.CHRONIC_WATERLOGGING,
                    timestampEpochMs = now - (50 * 60 * 1000),
                    sourceConfidenceAlpha = 0.86,
                    depthCm = 30,
                    severityScore = 0.70,
                    reporterSource = "IT Corridor Patrol",
                    description = "Buckingham canal backflow on OMR service lane."
                )
            )

            SimulationScenario.SUBWAY_CLOSURES_SPATE -> listOf(
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vyas_subway_fwd",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = now - (20 * 60 * 1000),
                    sourceConfidenceAlpha = 0.99,
                    depthCm = 65,
                    severityScore = 1.0,
                    reporterSource = "Police Control Room",
                    description = "Subway closed by barricades."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_egm_gengu_fwd",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = now - (30 * 60 * 1000),
                    sourceConfidenceAlpha = 0.95,
                    depthCm = 48,
                    severityScore = 0.90,
                    reporterSource = "Egmore Station Alert",
                    description = "Gengu Reddy subway impassable."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_panagal_usman_fwd",
                    category = HazardCategory.SUBWAY_INUNDATION,
                    timestampEpochMs = now - (45 * 60 * 1000),
                    sourceConfidenceAlpha = 0.93,
                    depthCm = 40,
                    severityScore = 0.85,
                    reporterSource = "GCC T. Nagar",
                    description = "Usman Rd subway waterlogged."
                )
            )

            SimulationScenario.CYCLONE_MICHAUNG_REPLAY -> listOf(
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vel_bypass_vj_fwd",
                    category = HazardCategory.FLASH_FLOOD_SURGE,
                    timestampEpochMs = now - (10 * 60 * 1000),
                    sourceConfidenceAlpha = 0.99,
                    depthCm = 95,
                    severityScore = 1.0,
                    reporterSource = "State Disaster Management",
                    description = "Massive inundation across Velachery basin."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_vel_vj_madi_fwd",
                    category = HazardCategory.ROAD_COLLAPSE,
                    timestampEpochMs = now - (30 * 60 * 1000),
                    sourceConfidenceAlpha = 0.97,
                    depthCm = 80,
                    severityScore = 1.0,
                    reporterSource = "GCC Engineering",
                    description = "Culvert erosion and deep flooding."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_said_vel_fwd",
                    category = HazardCategory.FLASH_FLOOD_SURGE,
                    timestampEpochMs = now - (20 * 60 * 1000),
                    sourceConfidenceAlpha = 0.92,
                    depthCm = 50,
                    severityScore = 0.85,
                    reporterSource = "Citizen Dispatch",
                    description = "Saidapet to Velachery low section inundated."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_tidel_perungudi_fwd",
                    category = HazardCategory.CHRONIC_WATERLOGGING,
                    timestampEpochMs = now - (40 * 60 * 1000),
                    sourceConfidenceAlpha = 0.90,
                    depthCm = 45,
                    severityScore = 0.80,
                    reporterSource = "OMR Road Patrol",
                    description = "Perungudi canal overflow."
                ),
                HazardObservation(
                    id = UUID.randomUUID().toString(),
                    edgeId = "e_tambaram_mudichur_fwd",
                    category = HazardCategory.FLASH_FLOOD_SURGE,
                    timestampEpochMs = now - (25 * 60 * 1000),
                    sourceConfidenceAlpha = 0.96,
                    depthCm = 75,
                    severityScore = 0.95,
                    reporterSource = "Tambaram Police",
                    description = "Mudichur low road impassable."
                )
            )

            SimulationScenario.DRY_WEATHER_BASELINE -> emptyList()
        }

        val entities = observations.map { HazardEntity.fromDomain(it, isWatchlist = false) }
        hazardDao.insertHazards(entities)
    }

    suspend fun insertObservation(observation: HazardObservation) {
        hazardDao.insertHazard(HazardEntity.fromDomain(observation))
    }
}
