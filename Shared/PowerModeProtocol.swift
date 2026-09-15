import Foundation

enum EnergyMode: Int, CaseIterable, Sendable {
    case automatic
    case lowPower
    case highPower
}

enum EnergyPowerSource: Int, Sendable {
    case battery
    case powerAdapter
}

enum PowerModeService {
    static let label = "io.github.dennich.StatusArc.PowerHelper"
    static let plistName = "io.github.dennich.StatusArc.PowerHelper.plist"

    // Increment this whenever the helper implementation or XPC contract changes.
    // A newly updated app asks an older running helper to exit, allowing launchd
    // to start the copy embedded in the new app bundle.
    static let implementationVersion = 1
}

@objc(StatusArcPowerModeHelperProtocol)
protocol PowerModeHelperProtocol {
    func helperVersion(withReply reply: @escaping (Int) -> Void)

    func setEnergyMode(
        _ mode: Int,
        for powerSource: Int,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    func stopForUpdate(withReply reply: @escaping () -> Void)
}
