import WidgetKit
import SwiftUI

@main
struct MirrorWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        // Gallery order (owner, 2026-11-13): Still Open first, the monthly report last.
        MirrorStillOpenWidget()
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
            MirrorScratchNoteControl()
        }
        #endif
    }
}
