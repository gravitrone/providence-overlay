import Foundation

public enum Activity: String, Codable, Sendable {
    case coding
    case browsing
    case meeting
    case writing
    case idle
    case general
}

public struct ClassifierInput: Sendable {
    public let bundleID: String?
    public let windowTitle: String
    public let axSummary: String
    public let ocrText: String?
    public let audioActive: Bool

    public init(
        bundleID: String?,
        windowTitle: String,
        axSummary: String,
        ocrText: String?,
        audioActive: Bool
    ) {
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.axSummary = axSummary
        self.ocrText = ocrText
        self.audioActive = audioActive
    }
}

public enum ActivityClassifier {
    public static let codingBundles: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.apple.Terminal", "com.googlecode.iterm2",
        "com.apple.dt.Xcode", "com.jetbrains.goland", "com.jetbrains.intellij",
        "com.github.atom", "com.sublimetext.4",
    ]
    public static let browserBundles: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser",
        "com.mozilla.firefox", "com.microsoft.edgemac",
    ]
    public static let meetingBundles: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.hnc.Discord", "com.apple.FaceTime",
    ]
    public static let writingBundles: Set<String> = [
        "com.apple.Pages", "md.obsidian", "com.microsoft.Word", "notion.id",
    ]

    public static func classify(_ input: ClassifierInput) -> Activity {
        if let b = input.bundleID {
            if meetingBundles.contains(b) { return .meeting }
            if input.audioActive && b.contains(".Chrome") { return .meeting }
            if codingBundles.contains(b) { return .coding }
            if writingBundles.contains(b) { return .writing }
            if browserBundles.contains(b) { return .browsing }
        }
        let ocrEmpty = (input.ocrText?.isEmpty ?? true)
        if input.axSummary.isEmpty && ocrEmpty { return .idle }
        return .general
    }
}
