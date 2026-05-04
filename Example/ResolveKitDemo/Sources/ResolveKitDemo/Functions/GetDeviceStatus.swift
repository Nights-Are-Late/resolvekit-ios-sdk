import ResolveKitAuthoring
import UIKit

/// Returns the current device's model, OS version, and battery state.
/// This function REQUIRES user approval since it accesses device information.
@ResolveKit(
    name: "get_device_status",
    description: "Returns information about the device including model name, iOS version, and current battery state.",
    timeout: 5,
    requiresApproval: true
)
struct GetDeviceStatus: ResolveKitFunction {
    /// A simple codable result type returned to the LLM.
    struct DeviceInfo: Codable {
        let modelName: String
        let osVersion: String
        let batteryState: String
        let batteryLevel: Double
    }

    func perform() async throws -> DeviceInfo {
        // Device model
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let modelName = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // OS version
        let osVersion = UIDevice.current.systemVersion

        // Battery info (requires enabling battery monitoring — safe to call, no permission needed)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryState: String
        switch UIDevice.current.batteryState {
        case .unknown:
            batteryState = "unknown"
        case .unplugged:
            batteryState = "unplugged"
        case .charging:
            batteryState = "charging"
        case .full:
            batteryState = "full"
        @unknown default:
            batteryState = "unknown"
        }
        let batteryLevel = UIDevice.current.batteryLevel >= 0
            ? Double(UIDevice.current.batteryLevel)
            : -1.0

        return DeviceInfo(
            modelName: modelName,
            osVersion: osVersion,
            batteryState: batteryState,
            batteryLevel: batteryLevel
        )
    }
}
