import Foundation

struct NoteEditPlan: Sendable, Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}
