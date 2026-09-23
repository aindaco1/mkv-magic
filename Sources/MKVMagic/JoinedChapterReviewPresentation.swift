import MKVMagicCore

enum JoinedChapterReviewPresentation {
    static func summary(for chapters: JoinedChapterComposition) -> String {
        "Joined chapter list • \(chapters.document.topLevelChapterCount) entries"
    }
}
