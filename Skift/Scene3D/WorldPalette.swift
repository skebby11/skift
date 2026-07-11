import AppKit

/// Shared art-direction palette for the procedural island.
///
/// Colors are intentionally matte and slightly desaturated. Saturated orange
/// is reserved for the rider and HUD so gameplay stays readable at a glance.
enum WorldPalette {
    static let sky = NSColor(red: 0.48, green: 0.68, blue: 0.84, alpha: 1)
    static let water = NSColor(red: 0.055, green: 0.31, blue: 0.45, alpha: 1)
    static let grass = NSColor(red: 0.36, green: 0.46, blue: 0.25, alpha: 1)
    static let sand = NSColor(red: 0.72, green: 0.58, blue: 0.32, alpha: 1)
    static let road = NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
    static let roadMarking = NSColor(red: 0.88, green: 0.84, blue: 0.72, alpha: 1)
    static let trunk = NSColor(red: 0.28, green: 0.18, blue: 0.11, alpha: 1)
    static let crown = NSColor(red: 0.20, green: 0.31, blue: 0.16, alpha: 1)
    static let rock = NSColor(red: 0.48, green: 0.45, blue: 0.39, alpha: 1)
    static let mountain = NSColor(red: 0.34, green: 0.39, blue: 0.38, alpha: 1)
    static let distantMountain = NSColor(red: 0.34, green: 0.43, blue: 0.53, alpha: 1)
    static let villageWall = NSColor(red: 0.82, green: 0.73, blue: 0.57, alpha: 1)
    static let terracotta = NSColor(red: 0.55, green: 0.25, blue: 0.14, alpha: 1)
    static let riderOrange = NSColor(red: 0.96, green: 0.34, blue: 0.06, alpha: 1)
    static let sun = NSColor(red: 1.0, green: 0.78, blue: 0.56, alpha: 1)
}
