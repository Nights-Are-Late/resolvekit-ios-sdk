import ResolveKitAuthoring

/// Sends a reminder to the user at a specified time.
/// This function REQUIRES user approval since it performs a write action.
@ResolveKit(
    name: "send_reminder",
    description: "Creates a reminder with a title and optional scheduled time. If no time is provided, the reminder is set for now.",
    timeout: 10,
    requiresApproval: true
)
struct SendReminder: ResolveKitFunction {
    /// Create a reminder with the given details.
    /// - Parameters:
    ///   - title: The reminder text.
    ///   - minutesFromNow: Optional delay in minutes. If nil or 0, the reminder fires immediately.
    func perform(title: String, minutesFromNow: Int?) async throws -> String {
        let delay = max(minutesFromNow ?? 0, 0)
        let fireDate = Date().addingTimeInterval(Double(delay) * 60)

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = .current

        let scheduled = delay > 0
            ? " (scheduled for \(formatter.string(from: fireDate)))"
            : " (immediate)"

        // In a real app, you would schedule a local notification here:
        // let content = UNMutableNotificationContent()
        // content.title = "ResolveKit Reminder"
        // content.body = title
        // let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(delay) * 60, repeats: false)
        // let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        // try await UNUserNotificationCenter.current().add(request)

        return "Reminder set: \"\(title)\"\(scheduled)"
    }
}
