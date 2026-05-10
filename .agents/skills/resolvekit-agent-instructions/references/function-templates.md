# ResolveKit Function Design Templates

## Template: Status Query (Read-Only)

Best for: "What is my subscription?", "What features do I have?"

### iOS
```swift
@ResolveKit(
    name: "check_subscription_status",
    description: "Returns the current user's subscription tier, whether they are on a free trial, and when their subscription renews or expires",
    requiresApproval: false
)
struct CheckSubscriptionStatus: ResolveKitFunction {
    func perform() async throws -> String {
        let user = await UserManager.shared.currentUser
        return """
        Plan: \(user.planName)
        Status: \(user.isTrialActive ? "Free Trial" : "Active")
        \(user.isTrialActive ? "Trial ends: \(user.trialEndDate)" : "Renews: \(user.renewalDate)"}
        """
    }
}
```

### Android
```kotlin
@ResolveKit(
    name = "check_subscription_status",
    description = "Returns the current user's subscription tier, whether they are on a free trial, and when their subscription renews or expires",
    requiresApproval = false
)
class CheckSubscriptionStatus(
    private val userRepository: UserRepository
) : ResolveKitFunction {
    override suspend fun perform(): Any? {
        val user = userRepository.getCurrentUser()
        return buildString {
            append("Plan: ${user.planName}\n")
            append("Status: ${if (user.isTrialActive) "Free Trial" else "Active"}\n")
            if (user.isTrialActive) {
                append("Trial ends: ${user.trialEndDate}")
            } else {
                append("Renews: ${user.renewalDate}")
            }
        }
    }
}
```

## Template: Data Fetch with Parameters

Best for: "Show my order history", "Get my settings"

### iOS
```swift
@ResolveKit(
    name: "get_order_history",
    description: "Returns the user's recent order history including order number, items, total amount, and current status",
    timeout: 15,
    requiresApproval: false
)
struct GetOrderHistory: ResolveKitFunction {
    func perform(limit: Int, includeCancelled: Bool) async throws -> String {
        let orders = await OrderService.shared.recentOrders(limit: limit)
        let filtered = includeCancelled ? orders : orders.filter { $0.status != .cancelled }
        return filtered.map { order in
            "Order #\(order.number): \(order.items) - \(order.total) - \(order.status)"
        }.joined(separator: "\n")
    }
}
```

### Android
```kotlin
@ResolveKit(
    name = "get_order_history",
    description = "Returns the user's recent order history including order number, items, total amount, and current status",
    timeout = 15,
    requiresApproval = false
)
class GetOrderHistory(
    private val orderRepository: OrderRepository
) : ResolveKitFunction {
    override suspend fun perform(limit: Int, includeCancelled: Boolean): Any? {
        val orders = orderRepository.getRecentOrders(limit)
        val filtered = if (includeCancelled) orders else orders.filter { it.status != OrderStatus.CANCELLED }
        return filtered.joinToString("\n") { order ->
            "Order #${order.number}: ${order.items} - ${order.total} - ${order.status}"
        }
    }
}
```

## Template: Navigation

Best for: "Take me to settings", "Open the profile page"

### iOS
```swift
@ResolveKit(
    name: "navigate_to_screen",
    description: "Opens a specific screen in the app. Available screens: settings, profile, billing, help, notifications",
    requiresApproval: false
)
struct NavigateToScreen: ResolveKitFunction {
    func perform(screenName: String) async throws -> String {
        guard let screen = ScreenType(rawValue: screenName.lowercased()) else {
            return "Available screens: settings, profile, billing, help, notifications"
        }
        await NavigationManager.shared.navigate(to: screen)
        return "Navigated to \(screenName)"
    }
}
```

### Android
```kotlin
@ResolveKit(
    name = "navigate_to_screen",
    description = "Opens a specific screen in the app. Available screens: settings, profile, billing, help, notifications",
    requiresApproval = false
)
class NavigateToScreen(
    private val navController: NavHostController
) : ResolveKitFunction {
    override suspend fun perform(screenName: String): Any? {
        val route = when (screenName.lowercase()) {
            "settings" -> "settings"
            "profile" -> "profile"
            "billing" -> "billing"
            "help" -> "help"
            "notifications" -> "notifications"
            else -> return "Available screens: settings, profile, billing, help, notifications"
        }
        navController.navigate(route)
        return "Navigated to $screenName"
    }
}
```

## Template: Mutation with Approval

Best for: "Cancel my subscription", "Delete my account", "Change my plan"

### iOS
```swift
@ResolveKit(
    name: "cancel_subscription",
    description: "Cancels the user's current subscription. This is irreversible and should only be done after confirming with the user. Returns confirmation of cancellation and the effective end date.",
    timeout: 30,
    requiresApproval: true
)
struct CancelSubscription: ResolveKitFunction {
    func perform(reason: String) async throws -> String {
        let result = await BillingService.shared.cancelSubscription(reason: reason)
        return "Subscription cancelled. Access continues until \(result.effectiveEndDate). Reason recorded: \(reason)"
    }
}
```

### Android
```kotlin
@ResolveKit(
    name = "cancel_subscription",
    description = "Cancels the user's current subscription. This is irreversible and should only be done after confirming with the user. Returns confirmation of cancellation and the effective end date.",
    timeout = 30,
    requiresApproval = true
)
class CancelSubscription(
    private val billingService: BillingService
) : ResolveKitFunction {
    override suspend fun perform(reason: String): Any? {
        val result = billingService.cancelSubscription(reason)
        return "Subscription cancelled. Access continues until ${result.effectiveEndDate}. Reason recorded: $reason"
    }
}
```

## Template: Feature Toggle

Best for: "Enable dark mode", "Turn on notifications", "Switch to pro features"

### iOS
```swift
@ResolveKit(
    name: "toggle_feature",
    description: "Enables or disables an app feature. Features: dark_mode, push_notifications, haptic_feedback, auto_sync",
    requiresApproval: false
)
struct ToggleFeature: ResolveKitFunction {
    func perform(featureName: String, enabled: Bool) async throws -> String {
        guard let feature = FeatureType(rawValue: featureName.lowercased()) else {
            return "Available features: dark_mode, push_notifications, haptic_feedback, auto_sync"
        }
        await FeatureManager.shared.set(feature, enabled: enabled)
        return "\(featureName) has been \(enabled ? "enabled" : "disabled")"
    }
}
```

## Function Pack Example

### iOS
```swift
enum UserSupportResolveKitPack: ResolveKitFunctionPack {
    static let packName = "user_support_pack"
    static let supportedPlatforms: [ResolveKitPlatform] = [.ios]
    static let functions: [any AnyResolveKitFunction.Type] = [
        CheckSubscriptionStatus.self,
        GetOrderHistory.self,
        NavigateToScreen.self,
        CancelSubscription.self
    ]
}
```

### Android
```kotlin
object UserSupportPack : ResolveKitFunctionPack {
    override val packName = "user_support_pack"
    override val supportedPlatforms = listOf(ResolveKitPlatform.ANDROID)
    override val functions: List<AnyResolveKitFunction> = listOf(
        CheckSubscriptionStatusResolveKitAdapter(userRepository),
        GetOrderHistoryResolveKitAdapter(orderRepository),
        NavigateToScreenResolveKitAdapter(navController),
        CancelSubscriptionResolveKitAdapter(billingService)
    )
}
```

## Description Writing Guide

The description is the MOST important part of a function definition. The LLM uses it to decide when to call the function.

### Good Descriptions
- "Returns the current user's subscription tier, whether they are on a free trial, and when their subscription renews or expires"
- "Cancels the user's current subscription. This is irreversible and should only be done after confirming with the user"
- "Opens a specific screen in the app. Available screens: settings, profile, billing, help, notifications"

### Bad Descriptions
- "Gets subscription" (too vague)
- "Does stuff" (useless)
- "Returns data" (no context about what data)

### Description Checklist
1. What does this function return/do?
2. What context does the LLM need to decide to use it?
3. Are there any warnings or caveats the LLM should know?
4. For navigation functions, what are the available options?
