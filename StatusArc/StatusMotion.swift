import Foundation
import SwiftUI

enum StatusMotion {
    static let expansionDuration: TimeInterval = 0.42
    static let expansion = Animation.spring(
        response: expansionDuration,
        dampingFraction: 1,
        blendDuration: 0
    )
    static let hover = Animation.easeOut(duration: 0.16)
}
