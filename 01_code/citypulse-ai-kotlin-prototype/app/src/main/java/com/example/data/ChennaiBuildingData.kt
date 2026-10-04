package com.example.data

import com.example.model.BuildingType
import com.example.model.GeoPoint
import com.example.model.MapBuilding

object ChennaiBuildingData {

    val BUILDINGS: List<MapBuilding> = listOf(
        // === NORTH & CENTRAL CHENNAI LANDMARKS ===
        MapBuilding(
            id = "b_central_station",
            name = "Chennai Central Terminus",
            center = GeoPoint(13.0835, 80.2755),
            widthKm = 0.55,
            heightKm = 0.35,
            heightStories = 12,
            type = BuildingType.TRANSIT_HUB,
            isProminentLandmark = true,
            rotationDeg = -12f
        ),
        MapBuilding(
            id = "b_ripon_building",
            name = "Ripon Building (GCC HQ)",
            center = GeoPoint(13.0850, 80.2725),
            widthKm = 0.45,
            heightKm = 0.30,
            heightStories = 10,
            type = BuildingType.HERITAGE_LANDMARK,
            isProminentLandmark = true,
            rotationDeg = 5f
        ),
        MapBuilding(
            id = "b_high_court",
            name = "Madras High Court",
            center = GeoPoint(13.0885, 80.2875),
            widthKm = 0.50,
            heightKm = 0.42,
            heightStories = 9,
            type = BuildingType.HERITAGE_LANDMARK,
            isProminentLandmark = true,
            rotationDeg = 20f
        ),
        MapBuilding(
            id = "b_egmore_station",
            name = "Chennai Egmore Railway Station",
            center = GeoPoint(13.0795, 80.2610),
            widthKm = 0.48,
            heightKm = 0.32,
            heightStories = 8,
            type = BuildingType.TRANSIT_HUB,
            isProminentLandmark = true,
            rotationDeg = -5f
        ),

        // === MOUNT ROAD / ANNA SALAI CORRIDOR ===
        MapBuilding(
            id = "b_lic_tower",
            name = "LIC Building",
            center = GeoPoint(13.0640, 80.2605),
            widthKm = 0.35,
            heightKm = 0.30,
            heightStories = 18,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = true,
            rotationDeg = -25f
        ),
        MapBuilding(
            id = "b_express_avenue",
            name = "Express Avenue Complex",
            center = GeoPoint(13.0585, 80.2640),
            widthKm = 0.52,
            heightKm = 0.40,
            heightStories = 11,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = false,
            rotationDeg = 15f
        ),
        MapBuilding(
            id = "b_marina_lighthouse",
            name = "Marina Lighthouse",
            center = GeoPoint(13.0395, 80.2795),
            widthKm = 0.28,
            heightKm = 0.28,
            heightStories = 15,
            type = BuildingType.HERITAGE_LANDMARK,
            isProminentLandmark = true,
            rotationDeg = 0f
        ),

        // === T. NAGAR COMMERCIAL CORE ===
        MapBuilding(
            id = "b_panagal_market",
            name = "T. Nagar Shopping District",
            center = GeoPoint(13.0425, 80.2335),
            widthKm = 0.55,
            heightKm = 0.38,
            heightStories = 9,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = false,
            rotationDeg = 30f
        ),
        MapBuilding(
            id = "b_usman_commercial",
            name = "South Usman Trade Hub",
            center = GeoPoint(13.0345, 80.2315),
            widthKm = 0.42,
            heightKm = 0.32,
            heightStories = 8,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = false,
            rotationDeg = 10f
        ),

        // === KOTHURPURAM & ADYAR INSTITUTIONAL ===
        MapBuilding(
            id = "b_anna_library",
            name = "Anna Centenary Library",
            center = GeoPoint(13.0135, 80.2370),
            widthKm = 0.45,
            heightKm = 0.36,
            heightStories = 12,
            type = BuildingType.INSTITUTIONAL,
            isProminentLandmark = true,
            rotationDeg = -15f
        ),
        MapBuilding(
            id = "b_iitm_research",
            name = "IIT Madras Research Park",
            center = GeoPoint(12.9935, 80.2385),
            widthKm = 0.58,
            heightKm = 0.46,
            heightStories = 14,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = true,
            rotationDeg = -10f
        ),
        MapBuilding(
            id = "b_iitm_academic",
            name = "IIT Madras Academic Complex",
            center = GeoPoint(12.9905, 80.2330),
            widthKm = 0.50,
            heightKm = 0.40,
            heightStories = 8,
            type = BuildingType.INSTITUTIONAL,
            isProminentLandmark = false,
            rotationDeg = 5f
        ),

        // === GUINDY & KATHIPARA ===
        MapBuilding(
            id = "b_olympia_tech",
            name = "Olympia Tech Park",
            center = GeoPoint(13.0115, 80.2075),
            widthKm = 0.48,
            heightKm = 0.38,
            heightStories = 13,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = true,
            rotationDeg = 25f
        ),
        MapBuilding(
            id = "b_kathipara_hub",
            name = "Kathipara Urban Center",
            center = GeoPoint(13.0080, 80.2035),
            widthKm = 0.44,
            heightKm = 0.35,
            heightStories = 10,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = false,
            rotationDeg = 0f
        ),

        // === OMR IT HIGHWAY CORRIDOR ===
        MapBuilding(
            id = "b_tidel_park",
            name = "TIDEL Park (OMR)",
            center = GeoPoint(12.9895, 80.2465),
            widthKm = 0.62,
            heightKm = 0.44,
            heightStories = 16,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = true,
            rotationDeg = -8f
        ),
        MapBuilding(
            id = "b_ascendas_it",
            name = "Ascendas International Tech Park",
            center = GeoPoint(12.9855, 80.2450),
            widthKm = 0.52,
            heightKm = 0.40,
            heightStories = 15,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = false,
            rotationDeg = 12f
        ),
        MapBuilding(
            id = "b_ramanujan_sez",
            name = "Ramanujan IT City SEZ",
            center = GeoPoint(12.9825, 80.2435),
            widthKm = 0.55,
            heightKm = 0.42,
            heightStories = 14,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = false,
            rotationDeg = -14f
        ),
        MapBuilding(
            id = "b_perungudi_wtc",
            name = "World Trade Center Perungudi",
            center = GeoPoint(12.9645, 80.2455),
            widthKm = 0.50,
            heightKm = 0.38,
            heightStories = 17,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = true,
            rotationDeg = 18f
        ),
        MapBuilding(
            id = "b_thoraipakkam_tech",
            name = "ASV Suntech Park",
            center = GeoPoint(12.9385, 80.2355),
            widthKm = 0.46,
            heightKm = 0.35,
            heightStories = 11,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = false,
            rotationDeg = 8f
        ),

        // === VELACHERY URBAN CLUSTERS ===
        MapBuilding(
            id = "b_phoenix_mall",
            name = "Phoenix Marketcity & Crest",
            center = GeoPoint(12.9920, 80.2170),
            widthKm = 0.65,
            heightKm = 0.48,
            heightStories = 15,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = true,
            rotationDeg = -20f
        ),
        MapBuilding(
            id = "b_velachery_transit",
            name = "Velachery MRTS Terminal Hub",
            center = GeoPoint(12.9775, 80.2225),
            widthKm = 0.46,
            heightKm = 0.36,
            heightStories = 9,
            type = BuildingType.TRANSIT_HUB,
            isProminentLandmark = false,
            rotationDeg = 15f
        ),

        // === AIRPORT & SOUTH-WEST ===
        MapBuilding(
            id = "b_airport_t1",
            name = "Chennai Airport Domestic Terminal",
            center = GeoPoint(12.9930, 80.1690),
            widthKm = 0.60,
            heightKm = 0.38,
            heightStories = 8,
            type = BuildingType.TRANSIT_HUB,
            isProminentLandmark = true,
            rotationDeg = -30f
        ),
        MapBuilding(
            id = "b_airport_t2",
            name = "Integrated International Terminal",
            center = GeoPoint(12.9960, 80.1740),
            widthKm = 0.58,
            heightKm = 0.36,
            heightStories = 9,
            type = BuildingType.TRANSIT_HUB,
            isProminentLandmark = true,
            rotationDeg = -25f
        ),
        MapBuilding(
            id = "b_dlf_cybercity",
            name = "DLF Cybercity Porur",
            center = GeoPoint(13.0185, 80.1770),
            widthKm = 0.64,
            heightKm = 0.45,
            heightStories = 13,
            type = BuildingType.TECH_PARK,
            isProminentLandmark = true,
            rotationDeg = 10f
        ),
        MapBuilding(
            id = "b_trade_centre",
            name = "Chennai Trade Centre",
            center = GeoPoint(13.0165, 80.1875),
            widthKm = 0.52,
            heightKm = 0.40,
            heightStories = 7,
            type = BuildingType.INSTITUTIONAL,
            isProminentLandmark = false,
            rotationDeg = -5f
        ),

        // === ANNA NAGAR & KOYAMBEDU ===
        MapBuilding(
            id = "b_anna_tower",
            name = "Anna Nagar Metro & Tower",
            center = GeoPoint(13.0875, 80.2135),
            widthKm = 0.48,
            heightKm = 0.38,
            heightStories = 12,
            type = BuildingType.COMMERCIAL_TOWER,
            isProminentLandmark = true,
            rotationDeg = 0f
        ),
        MapBuilding(
            id = "b_cmbt_bus",
            name = "Koyambedu CMBT Hub",
            center = GeoPoint(13.0695, 80.2045),
            widthKm = 0.65,
            heightKm = 0.45,
            heightStories = 8,
            type = BuildingType.TRANSIT_HUB,
            isProminentLandmark = true,
            rotationDeg = 20f
        ),

        // === SECONDARY URBAN FABRIC BLOCKS ===
        MapBuilding("b_u1", "Kilpauk Medical College", GeoPoint(13.0785, 80.2415), 0.38, 0.28, 7, BuildingType.INSTITUTIONAL),
        MapBuilding("b_u2", "Nungambakkam High Road Plaza", GeoPoint(13.0610, 80.2425), 0.36, 0.26, 8, BuildingType.COMMERCIAL_TOWER),
        MapBuilding("b_u3", "Mylapore Heritage Arcade", GeoPoint(13.0350, 80.2680), 0.40, 0.30, 6, BuildingType.HERITAGE_LANDMARK),
        MapBuilding("b_u4", "Besant Nagar Coastal Block", GeoPoint(12.9980, 80.2670), 0.38, 0.28, 7, BuildingType.URBAN_RESIDENTIAL),
        MapBuilding("b_u5", "Perambur Loco Works", GeoPoint(13.1040, 80.2380), 0.44, 0.32, 6, BuildingType.TRANSIT_HUB),
        MapBuilding("b_u6", "Pallavaram GST Retail Center", GeoPoint(12.9660, 80.1495), 0.40, 0.30, 7, BuildingType.COMMERCIAL_TOWER),
        MapBuilding("b_u7", "Tambaram Sanatorium Medical", GeoPoint(12.9270, 80.1250), 0.42, 0.32, 6, BuildingType.INSTITUTIONAL),
        MapBuilding("b_u8", "Radial Road SEZ Tower", GeoPoint(12.9510, 80.1870), 0.45, 0.34, 11, BuildingType.TECH_PARK)
    )
}
