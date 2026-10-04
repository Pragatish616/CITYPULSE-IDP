package com.example.data

import com.example.model.GeoPoint
import com.example.model.RoadEdge
import com.example.model.RoadNode
import com.example.model.TerrainPriorType

object ChennaiGraphData {

    val NODES = listOf(
        RoadNode("node_central", "Chennai Central", GeoPoint(13.0827, 80.2707), 6.0, false, "North Central"),
        RoadNode("node_egmore", "Egmore Junction", GeoPoint(13.0805, 80.2612), 8.0, false, "North Central"),
        RoadNode("node_gengu_reddy", "Gengu Reddy Subway", GeoPoint(13.0760, 80.2540), 2.5, false, "Egmore"),
        RoadNode("node_vyasarpadi", "Vyasarpadi Subway", GeoPoint(13.1110, 80.2580), 2.0, false, "North Chennai"),
        RoadNode("node_perambur", "Perambur Barracks", GeoPoint(13.1060, 80.2450), 7.0, false, "North Chennai"),
        RoadNode("node_basin_bridge", "Basin Bridge", GeoPoint(13.0990, 80.2720), 4.0, false, "North Chennai"),
        RoadNode("node_anna_nagar", "Anna Nagar Roundtana", GeoPoint(13.0850, 80.2150), 13.0, true, "North West"),
        RoadNode("node_kilpauk", "Kilpauk / Poonamallee Rd", GeoPoint(13.0780, 80.2400), 10.0, false, "Central West"),
        RoadNode("node_mount_road", "Mount Rd / Thousand Lights", GeoPoint(13.0580, 80.2520), 9.0, false, "Central"),
        RoadNode("node_panagal_park", "T. Nagar Panagal Park", GeoPoint(13.0410, 80.2340), 7.0, false, "Central South"),
        RoadNode("node_usman_subway", "South Usman Rd Subway", GeoPoint(13.0330, 80.2310), 3.0, false, "T. Nagar"),
        RoadNode("node_saidapet", "Saidapet (Adyar River Link)", GeoPoint(13.0210, 80.2230), 5.0, false, "Central South"),
        RoadNode("node_kathipara", "Guindy Kathipara Grade Separator", GeoPoint(13.0067, 80.2025), 16.0, true, "Guindy Elevated"),
        RoadNode("node_velachery_bypass", "Velachery 100ft Lake Bypass", GeoPoint(12.9810, 80.2190), 3.0, false, "Velachery Basin"),
        RoadNode("node_velachery_vijayanagar", "Velachery Vijayanagar Jn", GeoPoint(12.9730, 80.2220), 4.0, false, "Velachery"),
        RoadNode("node_madipakkam", "Madipakkam Lake Lowlands", GeoPoint(12.9650, 80.1980), 2.0, false, "South Basin"),
        RoadNode("node_tidel_park", "Tidel Park (OMR Start)", GeoPoint(12.9890, 80.2480), 7.0, false, "OMR IT Corridor"),
        RoadNode("node_perungudi_link", "Perungudi Canal Link", GeoPoint(12.9620, 80.2420), 3.0, false, "OMR Basin"),
        RoadNode("node_thoraipakkam", "Thoraipakkam OMR Jn", GeoPoint(12.9360, 80.2330), 6.0, false, "OMR South"),
        RoadNode("node_radial_road_mid", "200ft Radial Rd Elevated Ridge", GeoPoint(12.9490, 80.1850), 14.0, true, "Radial Highway"),
        RoadNode("node_pallavaram", "Pallavaram GST Highway", GeoPoint(12.9680, 80.1470), 15.0, true, "South West"),
        RoadNode("node_airport", "Chennai Airport / Meenambakkam", GeoPoint(12.9940, 80.1710), 12.0, true, "Airport Corridor"),
        RoadNode("node_tambaram", "Tambaram Sanatorium GST", GeoPoint(12.9250, 80.1230), 18.0, true, "Outer South"),
        RoadNode("node_mudichur", "Mudichur Low Corridor", GeoPoint(12.9150, 80.0880), 4.0, false, "Tambaram Basin"),
        RoadNode("node_adyar_shastri", "Adyar Shastri Nagar", GeoPoint(13.0030, 80.2560), 6.0, false, "Coastal South"),
        RoadNode("node_marina", "Marina Beach Road", GeoPoint(13.0500, 80.2820), 5.0, false, "East Coast"),
        RoadNode("node_thiruvanmiyur", "Thiruvanmiyur ECR Junction", GeoPoint(12.9830, 80.2590), 7.0, false, "East Coast")
    )

    val NODE_MAP: Map<String, RoadNode> = NODES.associateBy { it.id }

    // Helper to add bidirectional edges
    private fun createBiEdges(
        baseId: String,
        nodeA: String,
        nodeB: String,
        name: String,
        lengthMeters: Double,
        speedKmh: Double,
        prior: TerrainPriorType,
        isSubway: Boolean = false,
        isElevated: Boolean = false
    ): List<RoadEdge> {
        return listOf(
            RoadEdge("${baseId}_fwd", nodeA, nodeB, name, lengthMeters, speedKmh, prior, isSubway, isElevated),
            RoadEdge("${baseId}_rev", nodeB, nodeA, name, lengthMeters, speedKmh, prior, isSubway, isElevated)
        )
    }

    val EDGES: List<RoadEdge> = buildList {
        // North Chennai Links
        addAll(createBiEdges("e_cen_vyas", "node_central", "node_vyasarpadi", "Vyasarpadi Approach Rd", 3600.0, 35.0, TerrainPriorType.HIGH_FLOOD_PRONE))
        addAll(createBiEdges("e_vyas_subway", "node_vyasarpadi", "node_perambur", "Vyasarpadi Ganesapuram Subway", 1400.0, 25.0, TerrainPriorType.EXTREME_DEPRESSION, isSubway = true))
        addAll(createBiEdges("e_per_basin", "node_perambur", "node_basin_bridge", "Basin Bridge Express Link", 2200.0, 45.0, TerrainPriorType.MODERATE_PRONE))
        addAll(createBiEdges("e_cen_basin", "node_central", "node_basin_bridge", "Wall Tax Road", 1900.0, 30.0, TerrainPriorType.HIGH_FLOOD_PRONE))
        addAll(createBiEdges("e_cen_egm", "node_central", "node_egmore", "EVR Periyar Salai (Poonamallee)", 1800.0, 40.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_egm_gengu", "node_egmore", "node_gengu_reddy", "Gengu Reddy Subway", 850.0, 20.0, TerrainPriorType.EXTREME_DEPRESSION, isSubway = true))
        addAll(createBiEdges("e_gengu_kil", "node_gengu_reddy", "node_kilpauk", "Kilpauk Garden Link", 1500.0, 35.0, TerrainPriorType.MODERATE_PRONE))

        // Central Links
        addAll(createBiEdges("e_egm_kil", "node_egmore", "node_kilpauk", "Poonamallee High Rd Main", 2100.0, 45.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_kil_anna", "node_kilpauk", "node_anna_nagar", "New Avadi Rd - Anna Nagar", 3200.0, 50.0, TerrainPriorType.ELEVATED_RIDGE, isElevated = true))
        addAll(createBiEdges("e_cen_marina", "node_central", "node_marina", "Kamarajar Salai Coastal Way", 3800.0, 45.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_egm_mount", "node_egmore", "node_mount_road", "Anna Salai (Mount Road)", 2800.0, 45.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_mount_panagal", "node_mount_road", "node_panagal_park", "G.N. Chetty Road", 2400.0, 35.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_panagal_usman", "node_panagal_park", "node_usman_subway", "South Usman Road (Subway Section)", 1200.0, 20.0, TerrainPriorType.EXTREME_DEPRESSION, isSubway = true))
        addAll(createBiEdges("e_usman_saidapet", "node_usman_subway", "node_saidapet", "Saidapet Bazaar Link", 1600.0, 30.0, TerrainPriorType.HIGH_FLOOD_PRONE))
        addAll(createBiEdges("e_panagal_saidapet_fly", "node_panagal_park", "node_saidapet", "Anna Salai Elevated Flyover", 2300.0, 50.0, TerrainPriorType.ELEVATED_RIDGE, isElevated = true))

        // Adyar & Guindy Hubs
        addAll(createBiEdges("e_mount_marina", "node_mount_road", "node_marina", "Radhakrishnan Salai", 3100.0, 40.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_marina_adyar", "node_marina", "node_adyar_shastri", "Santhome High Rd - Adyar", 4200.0, 45.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_saidapet_kathipara", "node_saidapet", "node_kathipara", "Anna Salai Guindy Corridor", 2600.0, 55.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_saidapet_adyar", "node_saidapet", "node_adyar_shastri", "Sardar Patel Road", 3400.0, 45.0, TerrainPriorType.MODERATE_PRONE))
        addAll(createBiEdges("e_adyar_tidel", "node_adyar_shastri", "node_tidel_park", "Madhya Kailash - OMR Entrance", 1900.0, 40.0, TerrainPriorType.MODERATE_PRONE))
        addAll(createBiEdges("e_adyar_thiru", "node_adyar_shastri", "node_thiruvanmiyur", "Lattice Bridge Rd", 2200.0, 40.0, TerrainPriorType.DEFAULT_URBAN))

        // South & Velachery / OMR Links (Choke Points vs Elevated Alternatives)
        // 1. Choke Route: Saidapet -> Velachery Lake 100ft Bypass -> Madipakkam
        addAll(createBiEdges("e_said_vel", "node_saidapet", "node_velachery_bypass", "Velachery Main Rd to Bypass", 4100.0, 30.0, TerrainPriorType.EXTREME_DEPRESSION))
        addAll(createBiEdges("e_vel_bypass_vj", "node_velachery_bypass", "node_velachery_vijayanagar", "Velachery Lake Link (Low Inundation)", 1100.0, 25.0, TerrainPriorType.EXTREME_DEPRESSION))
        addAll(createBiEdges("e_vel_vj_madi", "node_velachery_vijayanagar", "node_madipakkam", "Madipakkam Lake Road Basin", 2100.0, 25.0, TerrainPriorType.EXTREME_DEPRESSION))

        // 2. OMR Canal Route (Perungudi low marsh):
        addAll(createBiEdges("e_tidel_perungudi", "node_tidel_park", "node_perungudi_link", "OMR Tollgate - Perungudi link", 3200.0, 40.0, TerrainPriorType.HIGH_FLOOD_PRONE))
        addAll(createBiEdges("e_perungudi_thoraipakkam", "node_perungudi_link", "node_thoraipakkam", "OMR Canal Expressway", 2900.0, 45.0, TerrainPriorType.MODERATE_PRONE))
        addAll(createBiEdges("e_thiru_tidel", "node_thiruvanmiyur", "node_tidel_park", "Thiruvanmiyur Signal Link", 1500.0, 35.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_thiru_thoraipakkam", "node_thiruvanmiyur", "node_thoraipakkam", "ECR-OMR Link Road", 4600.0, 50.0, TerrainPriorType.DEFAULT_URBAN))

        // 3. Elevated High-Ground Corridor: Guindy Kathipara -> Airport -> Pallavaram -> 200ft Radial Road -> Thoraipakkam
        addAll(createBiEdges("e_kathi_air", "node_kathipara", "node_airport", "GST Elevated Expressway Section 1", 3100.0, 65.0, TerrainPriorType.ELEVATED_RIDGE, isElevated = true))
        addAll(createBiEdges("e_air_palla", "node_airport", "node_pallavaram", "GST Elevated Corridor Section 2", 3400.0, 65.0, TerrainPriorType.ELEVATED_RIDGE, isElevated = true))
        addAll(createBiEdges("e_palla_radial", "node_pallavaram", "node_radial_road_mid", "200ft Radial Rd High-Ground Corridor", 4200.0, 60.0, TerrainPriorType.ELEVATED_RIDGE, isElevated = true))
        addAll(createBiEdges("e_radial_thorai", "node_radial_road_mid", "node_thoraipakkam", "200ft Radial Rd to OMR Junction", 4800.0, 60.0, TerrainPriorType.ELEVATED_RIDGE, isElevated = true))

        // Cross links
        addAll(createBiEdges("e_kathi_vel_bypass", "node_kathipara", "node_velachery_bypass", "Inner Ring Road (St Thomas Mt - Velachery)", 3800.0, 40.0, TerrainPriorType.HIGH_FLOOD_PRONE))
        addAll(createBiEdges("e_radial_madi", "node_radial_road_mid", "node_madipakkam", "Radial Rd South Madipakkam Connector", 2200.0, 35.0, TerrainPriorType.MODERATE_PRONE))

        // Far South Tambaram
        addAll(createBiEdges("e_palla_tambaram", "node_pallavaram", "node_tambaram", "GST Highway Tambaram", 4900.0, 60.0, TerrainPriorType.DEFAULT_URBAN))
        addAll(createBiEdges("e_tambaram_mudichur", "node_tambaram", "node_mudichur", "Mudichur Road (Low Basin)", 3100.0, 25.0, TerrainPriorType.EXTREME_DEPRESSION))
    }

    val EDGE_MAP: Map<String, RoadEdge> = EDGES.associateBy { it.id }

    /**
     * GCC Chronic Waterlogging Watchlist (Known historic hotspots)
     */
    val CHENNAI_WATCHLIST = listOf(
        WatchlistSpot("spot_vyasarpadi", "Vyasarpadi Ganesapuram Subway", "e_vyas_subway_fwd", 13.1110, 80.2580, "Severe railway subway depression; water pump failure during 50mm+ rain."),
        WatchlistSpot("spot_velachery_lake", "Velachery 100ft Bypass (Lake Breach)", "e_vel_bypass_vj_fwd", 12.9810, 80.2190, "Discharge channel overflow from Velachery Lake into Pallikaranai marsh."),
        WatchlistSpot("spot_usman_subway", "South Usman Road Subway", "e_panagal_usman_fwd", 13.0330, 80.2310, "Subway inundation under T. Nagar flyover; impassable for light vehicles."),
        WatchlistSpot("spot_madipakkam", "Madipakkam Lake Lowlands", "e_vel_vj_madi_fwd", 12.9650, 80.1980, "Low-lying basin between Madipakkam and Kilkattalai lakes."),
        WatchlistSpot("spot_gengu_reddy", "Gengu Reddy Subway (Egmore)", "e_egm_gengu_fwd", 13.0760, 80.2540, "Pedestrian and vehicle underpass connecting Poonamallee Rd with Egmore."),
        WatchlistSpot("spot_perungudi_canal", "Perungudi OMR Canal Junction", "e_tidel_perungudi_fwd", 12.9620, 80.2420, "Buckingham Canal culvert backflow onto IT expressway."),
        WatchlistSpot("spot_mudichur", "Mudichur Basin (Tambaram)", "e_tambaram_mudichur_fwd", 12.9150, 80.0880, "Adyar River headwaters overflow zone affecting Old Mudichur.")
    )

    data class WatchlistSpot(
        val id: String,
        val title: String,
        val edgeId: String,
        val lat: Double,
        val lon: Double,
        val floodVulnerabilityNote: String
    )
}
