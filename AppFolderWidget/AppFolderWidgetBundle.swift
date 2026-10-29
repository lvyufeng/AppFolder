import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen launchers keep independent configuration types.
@main
struct AppFolderWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 27.0, *) {
            DirectLaunchWidget()
            LockScreenLaunchWidget()
        }
    }
}
