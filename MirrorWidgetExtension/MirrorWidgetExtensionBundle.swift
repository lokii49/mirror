import WidgetKit
import SwiftUI

@main
struct MirrorWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        MirrorWriteWidget()
        MirrorEntriesMapWidget()
        MirrorMoodMapWidget()
        MirrorNudgeWidget()
        MirrorPromptWidget()
        MirrorWeeklyDigestWidget()
        MirrorMonthlyReportWidget()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            MirrorNewEntryControl()
            MirrorLogMoodControl()
        }
        #endif
    }
}
