import Foundation

// Decodes the small slice of LiveLessonViewModel.voicePayload (the on-device
// conversation-level voice-analysis JSON built by ConversationVoicePayload in
// the voice-analysis package) needed to show the user SPECIFIC delivery
// numbers -- pace, pitch variation, filler rate -- rather than only the
// engine's one-line Delivery grade. This is a separate read of the same
// on-device data the engine's voiceSummary is built from; it never talks to
// the server.
private struct VoiceAggregatesPayload: Decodable {
    struct Metric: Decodable {
        let value: Double?
        let status: String
    }
    struct Metrics: Decodable {
        let speechOnlyRateWpm: Metric
        let observedFillersPer100Words: Metric
        let timeWeightedWithinTurnPitchRangeSemitones: Metric
    }
    struct Aggregates: Decodable {
        let metrics: Metrics
    }
    let aggregates: Aggregates
}

// One measured, provisional row -- pace, pitch variation, or filler rate.
// `unit`/`target` describe the same product-hypothesis bands the per-turn
// scorer (voice-analysis/src/scoring.js) already uses; this just surfaces
// them for a whole conversation instead of computing its own scoring policy.
struct VoiceDeliveryMetricRow: Identifiable {
    let id: String
    let title: String
    let icon: String
    let value: Double?
    let unit: String
    let target: ClosedRange<Double>
    let targetLabel: String

    var isAvailable: Bool { value != nil }

    var band: String? {
        guard let value else { return nil }
        if value < target.lowerBound { return "below" }
        if value > target.upperBound { return "above" }
        return "within"
    }

    var valueText: String {
        guard let value else { return "Not enough recorded speech yet" }
        let rounded = (value * 10).rounded() / 10
        let formatted = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        return "\(formatted) \(unit)"
    }

    var detailText: String {
        guard let band else { return "Needs a longer or clearer recording to measure." }
        return "\(band == "within" ? "Within" : band == "below" ? "Below" : "Above") the provisional \(targetLabel) target."
    }
}

enum VoiceDeliveryMetrics {
    // Nil when there's no payload yet, it doesn't decode (an older/partial
    // shape), or nothing was recorded aloud this conversation -- callers
    // should simply not show the section rather than show empty rows.
    static func rows(from voicePayload: Data?) -> [VoiceDeliveryMetricRow]? {
        guard let voicePayload,
              let decoded = try? JSONDecoder().decode(VoiceAggregatesPayload.self, from: voicePayload) else { return nil }
        let metrics = decoded.aggregates.metrics
        return [
            VoiceDeliveryMetricRow(
                id: "pace", title: "Pace", icon: "gauge.medium",
                value: metrics.speechOnlyRateWpm.status == "unavailable" ? nil : metrics.speechOnlyRateWpm.value,
                unit: "words/minute", target: 120...180, targetLabel: "120-180 words/minute"
            ),
            VoiceDeliveryMetricRow(
                id: "pitch", title: "Pitch variation", icon: "waveform.path",
                value: metrics.timeWeightedWithinTurnPitchRangeSemitones.status == "unavailable" ? nil : metrics.timeWeightedWithinTurnPitchRangeSemitones.value,
                unit: "semitones of range", target: 3...8, targetLabel: "3-8 semitone"
            ),
            VoiceDeliveryMetricRow(
                id: "fillers", title: "Filler words", icon: "text.bubble",
                value: metrics.observedFillersPer100Words.status == "unavailable" ? nil : metrics.observedFillersPer100Words.value,
                unit: "per 100 words", target: 0...2, targetLabel: "0-2 per 100 words"
            ),
        ]
    }
}
