import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var hostingController: UIHostingController<NudgeContentView>?

    func didReceive(_ notification: UNNotification) {
        let state = NudgeContentState(content: notification.request.content)
        let rootView = NudgeContentView(state: state) { [weak self] in
            self?.openApp()
        }
        if let hosting = hostingController {
            hosting.rootView = rootView
        } else {
            let hosting = UIHostingController(rootView: rootView)
            addChild(hosting)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            hosting.didMove(toParent: self)
            hostingController = hosting
        }
    }

    private func openApp() {
        guard let url = URL(string: "mirror://write") else { return }
        extensionContext?.open(url, completionHandler: nil)
    }
}
