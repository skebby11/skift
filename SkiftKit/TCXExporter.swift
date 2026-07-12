import Foundation

/// Renders a recorded ride to Garmin TCX (Training Center XML) — the plain-XML
/// activity format Strava and most training platforms import.
///
/// The ride has no GPS coordinates (indoor), which Strava accepts. Power and
/// speed go in the ActivityExtension (`ns3`) namespace, like Garmin devices do.
///
/// DECISION (Plan.md M4): TCX before FIT — no binary SDK needed and Strava
/// imports it fine. REVIEW: confirm a real exported file uploads to Strava.
public enum TCXExporter {

    /// Builds the TCX document. Returns nil if the recording is empty.
    public static func export(recorder: RideRecorder) -> String? {
        guard let startDate = recorder.startDate, !recorder.samples.isEmpty,
              let summary = recorder.summary else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startString = iso.string(from: startDate)

        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(
            #"<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" "#
            + #"xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">"#
        )
        lines.append("  <Activities>")
        lines.append(#"    <Activity Sport="Biking">"#)
        lines.append("      <Id>\(startString)</Id>")
        lines.append(#"      <Lap StartTime="\#(startString)">"#)
        lines.append("        <TotalTimeSeconds>\(format(summary.durationSeconds))</TotalTimeSeconds>")
        lines.append("        <DistanceMeters>\(format(summary.distanceMeters))</DistanceMeters>")
        // Conventional cycling estimate: kJ of work ≈ kcal burned.
        lines.append("        <Calories>\(Int(summary.energyKilojoules.rounded()))</Calories>")
        lines.append("        <Intensity>Active</Intensity>")
        lines.append("        <TriggerMethod>Manual</TriggerMethod>")
        lines.append("        <Track>")

        for sample in recorder.samples {
            let time = iso.string(from: startDate.addingTimeInterval(sample.timeOffset))
            lines.append("          <Trackpoint>")
            lines.append("            <Time>\(time)</Time>")
            lines.append("            <AltitudeMeters>\(format(sample.elevationMeters))</AltitudeMeters>")
            lines.append("            <DistanceMeters>\(format(sample.distanceMeters))</DistanceMeters>")
            // TCX's Trackpoint_t sequence puts HeartRateBpm before Cadence.
            if let heartRate = sample.heartRateBpm {
                lines.append("            <HeartRateBpm><Value>\(heartRate)</Value></HeartRateBpm>")
            }
            if let cadence = sample.cadenceRpm {
                lines.append("            <Cadence>\(Int(cadence.rounded()))</Cadence>")
            }
            let speedMS = sample.speedKmh / 3.6
            var extensions = "<ns3:Speed>\(format(speedMS))</ns3:Speed>"
            if let power = sample.powerWatts {
                extensions += "<ns3:Watts>\(power)</ns3:Watts>"
            }
            lines.append("            <Extensions><ns3:TPX>\(extensions)</ns3:TPX></Extensions>")
            lines.append("          </Trackpoint>")
        }

        lines.append("        </Track>")
        lines.append("      </Lap>")
        lines.append("      <Creator xsi:type=\"Device_t\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><Name>Skift</Name><UnitId>0</UnitId><ProductID>0</ProductID></Creator>")
        lines.append("    </Activity>")
        lines.append("  </Activities>")
        lines.append("</TrainingCenterDatabase>")
        return lines.joined(separator: "\n")
    }

    /// Fixed-format numbers: TCX consumers dislike scientific notation and
    /// locale-dependent decimal separators.
    private static func format(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
