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
    }
}
