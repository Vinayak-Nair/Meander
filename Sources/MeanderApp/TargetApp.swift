import Foundation

/// An app Meander has dictated into, remembered so the dashboard can show and let
/// you tune its formatting profile.
struct TargetApp: Identifiable, Codable, Equatable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}
