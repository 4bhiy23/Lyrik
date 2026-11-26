import Foundation
import IOKit.pwr_mgt

/// Holds a display-sleep assertion while music plays (when the user wants it).
final class ScreenAwake {
    static let shared = ScreenAwake()
    private var assertionID: IOPMAssertionID = 0
    private(set) var held = false

    func set(_ on: Bool) {
        if on == held { return }
        if on {
            let status = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Lyrik is showing lyrics for playing music" as CFString,
                                                     &assertionID)
            held = status == kIOReturnSuccess
            Log.write(held ? "screen awake: assertion held" : "screen awake: assertion FAILED (\(status))")
        } else {
            IOPMAssertionRelease(assertionID)
            held = false
            Log.write("screen awake: assertion released")
        }
    }
}
