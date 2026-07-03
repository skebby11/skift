import Foundation

/// The classic 6-zone (Coggan) power model, relative to FTP.
/// Pure and testable; the UI maps zones to colors.
public enum PowerZone: Int, CaseIterable, Equatable {
    case recovery = 1   // < 55% FTP
    case endurance = 2  // 55–75%
    case tempo = 3      // 76–90%
    case threshold = 4  // 91–105%
    case vo2max = 5     // 106–120%
    case anaerobic = 6  // > 120%

    /// Zone for a given instantaneous power. FTP ≤ 0 degrades to recovery
    /// rather than dividing by zero.
    public static func zone(forPower watts: Int, ftp: Double) -> PowerZone {
        guard ftp > 0 else { return .recovery }
        let fraction = Double(watts) / ftp
        switch fraction {
        case ..<0.55: return .recovery
        case ..<0.76: return .endurance
        case ..<0.91: return .tempo
        case ..<1.06: return .threshold
        case ..<1.21: return .vo2max
        default: return .anaerobic
        }
    }

    /// Training name, as shown on the HUD chip.
    public var name: String {
        switch self {
        case .recovery: return "Recovery"
        case .endurance: return "Endurance"
        case .tempo: return "Tempo"
        case .threshold: return "Threshold"
        case .vo2max: return "VO2 Max"
        case .anaerobic: return "Anaerobic"
        }
    }
}
