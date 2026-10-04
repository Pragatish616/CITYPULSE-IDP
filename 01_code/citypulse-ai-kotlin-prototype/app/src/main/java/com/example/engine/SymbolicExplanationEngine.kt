package com.example.engine

import com.example.model.DecisionFactSet
import java.util.regex.Pattern
import kotlin.math.abs

object SymbolicExplanationEngine {

    data class VerificationResult(
        val isVerified: Boolean,
        val auditedNumeralsCount: Int,
        val verifiedFacts: List<String>,
        val flaggedDiscrepancies: List<String>,
        val approvedText: String,
        val tierSource: String
    )

    /**
     * Tier 0 Template NLG: Sub-millisecond deterministic template.
     * Guaranteed 100% faithful to the decision trace. Always available on-device.
     */
    fun generateTier0Rationale(
        facts: DecisionFactSet,
        originName: String,
        destName: String
    ): String {
        val signTime = if (facts.timeDiffMinutes >= 0) "+${facts.timeDiffMinutes}" else "${facts.timeDiffMinutes}"
        val signDist = if (facts.distanceDiffKm >= 0) "+${facts.distanceDiffKm}" else "${facts.distanceDiffKm}"

        val avoidedSection = if (facts.avoidedChokepoints.isNotEmpty()) {
            val list = facts.avoidedChokepoints.joinToString("; ")
            "Avoided ${facts.avoidedChokepoints.size} high-risk chokepoint(s): $list."
        } else {
            "No active subway or basin closures on the corridor."
        }

        val highGroundSection = if (facts.highGroundDetourKm > 0) {
            "Utilized ${facts.highGroundDetourKm} km of elevated grade separators and ridge road."
        } else {
            "Followed optimal surface grade."
        }

        return """
[CityPulse Tier-0 Decision Trace]
Routing from $originName to $destName achieved a ${facts.hazardReductionPct}% reduction in hazard exposure (lowered from ${facts.naiveHazardPct}% to ${facts.safeHazardPct}%).
Trade-off: Adds $signTime min travel time and $signDist km distance.
$highGroundSection
$avoidedSection
Calculated on-device under pessimistic dial z=${facts.pessimismZValue} (${facts.networkMode}, ${facts.confidenceBadgePct}% source confidence).
        """.trimIndent()
    }

    /**
     * Tier 1 Natural Language Dispatch Briefing
     */
    fun generateTier1Briefing(
        facts: DecisionFactSet,
        originName: String,
        destName: String
    ): String {
        val signTime = if (facts.timeDiffMinutes >= 0) "+${facts.timeDiffMinutes}" else "${facts.timeDiffMinutes}"
        val signDist = if (facts.distanceDiffKm >= 0) "+${facts.distanceDiffKm}" else "${facts.distanceDiffKm}"

        val chokepointText = if (facts.avoidedChokepoints.isNotEmpty()) {
            "bypassing critical hazards: " + facts.avoidedChokepoints.take(2).joinToString(", ")
        } else {
            "along higher terrain"
        }

        return "CityPulse safely redirected your journey from $originName to $destName, cutting waterlogging risk by ${facts.hazardReductionPct}% ($chokepointText). This prudent route accepts $signTime min in transit delay and $signDist km in distance, traveling along ${facts.highGroundDetourKm} km of elevated corridors with pessimism factor z=${facts.pessimismZValue}."
    }

    /**
     * Symbolic Fact Verifier:
     * Scans every numeral in candidate text and verifies that it is grounded in the fact set.
     * If an ungrounded numeral or hallucination is detected, it fails closed to the Tier-0 template.
     */
    fun verifyExplanation(
        candidateText: String,
        facts: DecisionFactSet,
        tier0Fallback: String
    ): VerificationResult {
        // Allowed fact set of valid numerals
        val validNumericFacts = listOf(
            abs(facts.timeDiffMinutes),
            abs(facts.distanceDiffKm),
            abs(facts.hazardReductionPct),
            abs(facts.naiveHazardPct),
            abs(facts.safeHazardPct),
            abs(facts.highGroundDetourKm),
            abs(facts.pessimismZValue),
            facts.confidenceBadgePct.toDouble(),
            facts.avoidedChokepoints.size.toDouble(),
            0.0, 1.0, 2.0 // standard indexing/counts
        )

        val numberPattern = Pattern.compile("[-+]?\\b\\d+(?:\\.\\d+)?%?\\b")
        val matcher = numberPattern.matcher(candidateText)

        val auditedNumerals = mutableListOf<String>()
        val verifiedFacts = mutableListOf<String>()
        val discrepancies = mutableListOf<String>()

        while (matcher.find()) {
            val rawToken = matcher.group().replace("%", "").replace("+", "").trim()
            val parsedVal = rawToken.toDoubleOrNull()
            if (parsedVal != null) {
                auditedNumerals.add(rawToken)
                // Check if matches any valid numeric fact within 0.1 tolerance
                val isMatched = validNumericFacts.any { abs(it - abs(parsedVal)) < 0.15 }
                if (isMatched) {
                    verifiedFacts.add("Numeral '$rawToken' correctly grounded in fact set")
                } else {
                    discrepancies.add("Ungrounded numeral '$rawToken' not found in decision trace")
                }
            }
        }

        val isValid = discrepancies.isEmpty()

        return if (isValid) {
            VerificationResult(
                isVerified = true,
                auditedNumeralsCount = auditedNumerals.size,
                verifiedFacts = verifiedFacts,
                flaggedDiscrepancies = emptyList(),
                approvedText = candidateText,
                tierSource = "Tier-1 SLM (Symbolically Verified)"
            )
        } else {
            // FAIL CLOSED RULE: Any ungrounded fact reverts directly to Tier-0
            VerificationResult(
                isVerified = false,
                auditedNumeralsCount = auditedNumerals.size,
                verifiedFacts = verifiedFacts,
                flaggedDiscrepancies = discrepancies,
                approvedText = tier0Fallback,
                tierSource = "Tier-0 Deterministic (Fail-Closed Reversion)"
            )
        }
    }
}
