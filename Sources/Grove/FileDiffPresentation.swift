import Foundation

/// Small presentation decisions prepared alongside the diff on the Git read task.
/// Keeping these values avoids reparsing the entire patch in SwiftUI's body.
struct FileDiffPresentation {
    var oldPath: String? = nil
    var hasSummary = false

    static func prepare(_ text: String) -> FileDiffPresentation {
        let files = CommitPatch.parse(text, prepareDiff: false).files
        return FileDiffPresentation(oldPath: files.first?.oldPath,
                                    hasSummary: files.contains { $0.summaryTitle != nil })
    }
}
