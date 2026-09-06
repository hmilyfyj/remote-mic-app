import CoreGraphics
import Foundation

/// Unmarked global Fn events have unknown device provenance. They only reserve
/// the external voice path; the Bluetooth callback supplies the remote identity.
struct SourceMicrophoneFnState {
    private(set) var externalDown = false
    private(set) var externalToggleActive = false
    private var suppressUntilRelease = false

    var externalVoiceBusy: Bool { externalDown || externalToggleActive || suppressUntilRelease }

    mutating func handle(pressed: Bool, synthetic: Bool, remoteBusy: Bool, tapMode: Bool) -> Bool {
        guard !synthetic else { return false }
        if remoteBusy || suppressUntilRelease {
            suppressUntilRelease = pressed
            return true
        }
        guard pressed != externalDown else { return false }
        externalDown = pressed
        if !pressed, tapMode { externalToggleActive.toggle() }
        return false
    }

    mutating func seed(pressed: Bool) { externalDown = pressed }
}

final class SourceMicrophoneFnMonitor {
    private let syntheticMarker: Int64
    private let logger: (String) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = SourceMicrophoneFnState()
    var remoteBusy: () -> Bool = { false }
    var tapMode: () -> Bool = { false }
    var onUnavailable: () -> Void = {}
    var externalVoiceBusy: Bool { state.externalVoiceBusy }
    var isRunning: Bool { tap.map(CGEvent.tapIsEnabled) ?? false }

    init(syntheticMarker: Int64, logger: @escaping (String) -> Void = { _ in }) {
        self.syntheticMarker = syntheticMarker
        self.logger = logger
    }

    func start() -> Bool {
        if isRunning { return true }
        stop()
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<SourceMicrophoneFnMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        state.seed(pressed: CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn))
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isRunning
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        state = SourceMicrophoneFnState()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            onUnavailable()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .flagsChanged, event.getIntegerValueField(.keyboardEventKeycode) == 63 else { return false }
        let pressed = event.flags.contains(.maskSecondaryFn)
        let synthetic = event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
        let suppressed = state.handle(
            pressed: pressed,
            synthetic: synthetic,
            remoteBusy: remoteBusy(),
            tapMode: tapMode()
        )
        if !synthetic {
            logger("VOICE SOURCE phase=observed source=unknown edge=\(pressed ? "down" : "up") suppressed=\(suppressed)")
        }
        return suppressed
    }

    deinit { stop() }
}
