import UIKit

/// Exists solely to catch background-download session relaunches. The system
/// hands us a completion handler to call once the session's queued events have
/// been replayed; DownloadManager calls it from urlSessionDidFinishEvents.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var backgroundSessionCompletionHandler: (() -> Void)?

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        Self.backgroundSessionCompletionHandler = completionHandler
    }
}
