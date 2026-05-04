import ResolveKitAuthoring

/// Returns the current local time on the device.
/// This function does NOT require user approval since it's read-only.
@ResolveKit(
    name: "get_local_time",
    description: "Returns the current local time on the device.",
    timeout: 5,
    requiresApproval: false
)
struct GetLocalTime: ResolveKitFunction {
    func perform() async throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
