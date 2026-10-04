package com.example.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.example.model.HazardCategory
import com.example.model.HazardObservation

@Entity(tableName = "hazard_observations")
data class HazardEntity(
    @PrimaryKey
    val id: String,
    val edgeId: String,
    val categoryName: String,
    val timestampEpochMs: Long,
    val sourceConfidenceAlpha: Double,
    val depthCm: Int,
    val severityScore: Double,
    val reporterSource: String,
    val description: String,
    val isChronicWatchlist: Boolean = false,
    val locationTitle: String = ""
) {
    fun toDomain(): HazardObservation {
        val cat = try {
            HazardCategory.valueOf(categoryName)
        } catch (e: Exception) {
            HazardCategory.CHRONIC_WATERLOGGING
        }
        return HazardObservation(
            id = id,
            edgeId = edgeId,
            category = cat,
            timestampEpochMs = timestampEpochMs,
            sourceConfidenceAlpha = sourceConfidenceAlpha,
            depthCm = depthCm,
            severityScore = severityScore,
            reporterSource = reporterSource,
            description = description
        )
    }

    companion object {
        fun fromDomain(domain: HazardObservation, isWatchlist: Boolean = false, title: String = ""): HazardEntity {
            return HazardEntity(
                id = domain.id,
                edgeId = domain.edgeId,
                categoryName = domain.category.name,
                timestampEpochMs = domain.timestampEpochMs,
                sourceConfidenceAlpha = domain.sourceConfidenceAlpha,
                depthCm = domain.depthCm,
                severityScore = domain.severityScore,
                reporterSource = domain.reporterSource,
                description = domain.description,
                isChronicWatchlist = isWatchlist,
                locationTitle = title
            )
        }
    }
}
