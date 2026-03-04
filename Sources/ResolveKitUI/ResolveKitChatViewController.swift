import Combine
import SwiftUI

#if os(iOS)
import UIKit

@MainActor
public final class ResolveKitChatViewController: UIHostingController<ResolveKitChatView> {
    public let runtime: ResolveKitRuntime

    private var cancellables: Set<AnyCancellable> = []

    public init(runtime: ResolveKitRuntime) {
        self.runtime = runtime
        super.init(rootView: ResolveKitChatView(runtime: runtime))
        applyNavigationStyle()
        bindRuntime()
    }

    public convenience init(configuration: ResolveKitConfiguration) {
        self.init(runtime: ResolveKitRuntime(configuration: configuration))
    }

    @available(*, unavailable, message: "Use init(runtime:) or init(configuration:) instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyNavigationStyle()
    }

    private func bindRuntime() {
        applyNavigationStyle()
        title = runtime.chatTitle
        runtime.$chatTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.title = $0 }
            .store(in: &cancellables)
    }

    private func applyNavigationStyle() {
        navigationItem.largeTitleDisplayMode = .never
    }
}
#elseif os(macOS)
import AppKit

@MainActor
public final class ResolveKitChatViewController: NSHostingController<ResolveKitChatView> {
    public let runtime: ResolveKitRuntime

    private var cancellables: Set<AnyCancellable> = []

    public init(runtime: ResolveKitRuntime) {
        self.runtime = runtime
        super.init(rootView: ResolveKitChatView(runtime: runtime))
        bindRuntime()
    }

    public convenience init(configuration: ResolveKitConfiguration) {
        self.init(runtime: ResolveKitRuntime(configuration: configuration))
    }

    @available(*, unavailable, message: "Use init(runtime:) or init(configuration:) instead.")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindRuntime() {
        title = runtime.chatTitle
        runtime.$chatTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.title = $0 }
            .store(in: &cancellables)
    }
}
#endif
