import Foundation

enum NoteRevealPolicy {
    static func revealedLines(
        selection: NSRange, markdown: NoteMarkdown, isFocused: Bool
    ) -> IndexSet {
        guard isFocused, selection.location != NSNotFound else { return IndexSet() }
        var revealed = IndexSet(integersIn: markdown.lineIndexes(intersecting: selection))
        guard let first = revealed.first, let last = revealed.last else { return revealed }
        for block in markdown.fenceBlocks where block.overlaps(first...last) {
            revealed.insert(block.lowerBound)
            revealed.insert(block.upperBound)
        }
        return revealed
    }

    static func shifted(
        _ revealed: IndexSet, editedOldLines: Range<Int>, editedNewLines: Range<Int>
    ) -> IndexSet {
        let delta = editedNewLines.count - editedOldLines.count
        var shifted = IndexSet()
        for index in revealed where !editedOldLines.contains(index) {
            shifted.insert(index < editedOldLines.lowerBound ? index : index + delta)
        }
        shifted.insert(integersIn: editedNewLines)
        return shifted
    }
}
