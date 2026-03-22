import Foundation

enum A11yID {
    static let mainWindow = "swiftvj.main.window"
    static let sidebarSection = "swiftvj.sidebar.section"
    static let detailSection = "swiftvj.detail.section"
    static let sidebarList = "swiftvj.sidebar.list"
    static let toolbarPhasePicker = "swiftvj.toolbar.phase"

    static func sidebarTab(_ name: String) -> String {
        "swiftvj.sidebar.\(name.lowercased())"
    }

    static let karaokeLoadTestButton = "swiftvj.karaoke.loadTest"
    static let karaokeAutoScrollToggle = "swiftvj.karaoke.autoScroll"
    static let karaokePrevButton = "swiftvj.karaoke.prev"
    static let karaokeNextButton = "swiftvj.karaoke.next"

    static let karaokeSettingsAnimationPicker = "swiftvj.karaoke.settings.animation"
    static func karaokePreset(_ name: String) -> String {
        "swiftvj.karaoke.settings.preset.\(name.lowercased())"
    }
    static let karaokeSettingsPreviewLoadTest = "swiftvj.karaoke.settings.preview.loadTest"
    static let karaokeSettingsPreviewPrev = "swiftvj.karaoke.settings.preview.prev"
    static let karaokeSettingsPreviewNext = "swiftvj.karaoke.settings.preview.next"

    static let launchpadStatus = "swiftvj.launchpad.status"
    static let launchpadLearnButton = "swiftvj.launchpad.learn"
    static let launchpadRunTestButton = "swiftvj.launchpad.runTest"

    static let masterLaunchAllButton = "swiftvj.master.launchAll"
    static let masterLaunchDropZone = "swiftvj.master.launchDropZone"
    static let masterAddCommandButton = "swiftvj.master.addCommand"

    static let songDemoPlayButton = "swiftvj.song.demoPlay"

    static let moodboardCanvas = "swiftvj.moodboard.canvas"
    static let moodboardPhaseBar = "swiftvj.moodboard.phasebar"
    static let moodboardLibrary = "swiftvj.moodboard.library"
    static let moodboardDetail = "swiftvj.moodboard.detail"
}
