import AppKit

/// Puts windows into a private window-server space whose absolute level sits above the
/// lock screen. Uses SkyLight (private) symbols resolved at runtime; if any are missing
/// the overlay simply stays an ordinary window and the lock screen hides it.
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    /// Absolute level the lock screen's notification layer uses.
    private static let aboveLockScreenLevel: Int32 = 400

    private var connection: Int32 = 0
    private var space: UInt64 = 0
    private var addWindows: SpaceAddWindows?
    private(set) var isAvailable = false

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            Log.write("skylight: framework unavailable")
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { Log.write("skylight: missing \(name)"); return nil }
            return unsafeBitCast(p, to: type)
        }
        guard let mainConnection = sym("SLSMainConnectionID", MainConnectionID.self),
              let create = sym("SLSSpaceCreate", SpaceCreate.self),
              let setLevel = sym("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
              let show = sym("SLSShowSpaces", ShowSpaces.self),
              let add = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", SpaceAddWindows.self) else { return }

        connection = mainConnection()
        space = create(connection, 1, 0)
        guard space != 0 else { Log.write("skylight: could not create a space"); return }
        _ = setLevel(connection, space, Self.aboveLockScreenLevel)
        _ = show(connection, [NSNumber(value: space)] as CFArray)
        addWindows = add
        isAvailable = true
        Log.write("skylight: lock-screen space \(space) ready")
    }

    /// Moves `window` into the above-lock-screen space. Call after it has a window number.
    func adopt(_ window: NSWindow) {
        guard let addWindows, window.windowNumber > 0 else { return }
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}
