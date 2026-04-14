import Foundation
import IOKit.ps

/// Phase 10: lightweight battery introspection.
/// Returns the primary power source state or a safe "on AC, full charge"
/// fallback when no battery is available (e.g. desktop Macs).
struct BatteryStatus {
    let onBattery: Bool
    let level: Double  // 0.0 - 1.0
}

enum BatteryMonitor {
    static func current() -> BatteryStatus {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sourcesRaw = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue()
        let sources = sourcesRaw as Array
        for src in sources {
            let cfSrc = src as CFTypeRef
            guard let info = IOPSGetPowerSourceDescription(snapshot, cfSrc).takeUnretainedValue() as? [String: Any] else { continue }
            let state = info[kIOPSPowerSourceStateKey as String] as? String
            let capacity = info[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maxCap = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let level = maxCap > 0 ? Double(capacity) / Double(maxCap) : 1.0
            let onBattery = state == (kIOPSBatteryPowerValue as String)
            return BatteryStatus(onBattery: onBattery, level: level)
        }
        return BatteryStatus(onBattery: false, level: 1.0)
    }
}
