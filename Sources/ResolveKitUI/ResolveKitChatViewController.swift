import Combine
import SwiftUI

enum ResolveKitReloadButtonPolicy {
    static func isEnabled(initialFetchCompleted: Bool) -> Bool {
        initialFetchCompleted
    }
}

#if os(iOS)
import UIKit

@MainActor
public final class ResolveKitChatViewController: UIHostingController<ResolveKitChatView> {
    public let runtime: ResolveKitRuntime

    private var cancellables: Set<AnyCancellable> = []
    private lazy var reloadBarButtonItem: UIBarButtonItem = {
        let action = UIAction { [weak self] _ in
            guard let self else { return }
            self.runtime.prepareForReloadWithNewSession()
            Task { @MainActor in
                await self.runtime.reloadWithNewSession()
            }
        }

        return UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            primaryAction: action
        )
    }()

    public init(runtime: ResolveKitRuntime) {
        self.runtime = runtime
        super.init(rootView: ResolveKitChatView(runtime: runtime))
        applyNavigationChrome()
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
        applyNavigationChrome()
    }

    private func bindRuntime() {
        applyNavigationChrome()
        applyChatTitle(runtime.chatTitle)
        reloadBarButtonItem.isEnabled = ResolveKitReloadButtonPolicy.isEnabled(
            initialFetchCompleted: runtime.initialFetchCompleted
        )
        runtime.$chatTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyChatTitle($0) }
            .store(in: &cancellables)
        runtime.$initialFetchCompleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completed in
                self?.reloadBarButtonItem.isEnabled = ResolveKitReloadButtonPolicy.isEnabled(
                    initialFetchCompleted: completed
                )
            }
            .store(in: &cancellables)
    }

    private func applyNavigationChrome() {
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = reloadBarButtonItem
    }

    private func applyChatTitle(_ title: String) {
        self.title = title
        navigationItem.title = title
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
        applyChatTitle(runtime.chatTitle)
        runtime.$chatTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyChatTitle($0) }
            .store(in: &cancellables)
    }

    private func applyChatTitle(_ title: String) {
        self.title = title
    }
}
#endif
