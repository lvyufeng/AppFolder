#if os(iOS) && canImport(WidgetKit)
import WidgetKit

/// Durable layouts and artwork are read by both launchers. Transient Home
/// Screen navigation must continue to reload only the direct-launch kind.
public enum AppFolderWidgetRefresh {
    public static func libraryChanged() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppFolderShared.directLaunchWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: AppFolderShared.lockScreenWidgetKind)
    }
}
#endif
