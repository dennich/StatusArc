import Foundation
import QuartzCore
import SwiftUI

enum StatusMotion {
    static let expansionDuration: TimeInterval = 0.30
    static let expansion = Animation.timingCurve(
        0.22, 1.0, 0.36, 1.0,
        duration: expansionDuration
    )
    static let expansionTimingFunction = CAMediaTimingFunction(
        controlPoints: 0.22, 1.0, 0.36, 1.0
    )
    static let hover = Animation.easeOut(duration: 0.16)
}
