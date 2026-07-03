import Foundation
import SkiftKit

/// Fabricates trainer data for demo mode, so the whole game is playable on
/// any Mac without a trainer: the ride HUD, physics, recording and summary
/// all run off this exactly as they would off the D500 (same `dataSource`
/// closure into the engine; the trainer-control side is simply nil).
final class DemoPowerSource: ObservableObject {

    /// Watts "pedaled" right now — bound to a slider in the ride screen.
    @Published var watts: Double = 150

    /// Builds a plausible trainer notification: cadence loosely follows
    /// power (60 rpm soft-pedaling → ~95 rpm hammering), no heart rate.
    func currentData() -> FTMS.IndoorBikeData {
        FTMS.IndoorBikeData(
            cadenceRpm: watts > 10 ? min(60 + watts / 8, 110) : 0,
            powerWatts: Int(watts)
        )
    }
}
