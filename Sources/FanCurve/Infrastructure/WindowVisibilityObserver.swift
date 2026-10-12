import AppKit
import Combine
import SwiftUI

struct WindowVisibilityObserver: NSViewRepresentable {
    let onVisibilityChanged: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onVisibilityChanged = onVisibilityChanged
        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.onVisibilityChanged = onVisibilityChanged
    }

    final class VisibilityView: NSView {
        var onVisibilityChanged: (@MainActor (Bool) -> Void)?
        private var subscriptions: [AnyCancellable] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            subscriptions.removeAll()
            guard let window else {
                onVisibilityChanged?(false)
                return
            }

            for name in [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification
            ] {
                NotificationCenter.default.publisher(for: name, object: window)
                    .sink { [weak self] notification in
                        let closing = notification.name == NSWindow.willCloseNotification
                        Task { @MainActor [weak self] in
                            if closing {
                                self?.onVisibilityChanged?(false)
                            } else {
                                self?.reportVisibility()
                            }
                        }
                    }
                    .store(in: &subscriptions)
            }
            reportVisibility()
        }

        private func reportVisibility() {
            let visible = window.map {
                $0.occlusionState.contains(.visible) && !$0.isMiniaturized
            } ?? false
            onVisibilityChanged?(visible)
        }
    }
}
