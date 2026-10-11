import AppKit
import SwiftUI

struct TerminalLogView: NSViewRepresentable {
    let run: CommandRun

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let inset = CGSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xs)
    private static let tailSlack = Theme.Spacing.followTailSlack

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var runID: UUID?
        var generation = -1
        var revision = 0
        var interpreter = ANSIInterpreter()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        textView.textContainer?.lineFragmentPadding = 0
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }
        let coordinator = context.coordinator
        let following = isAtBottom(scrollView)

        let isSameRun = coordinator.runID == run.id && coordinator.generation == run.generation
        guard !isSameRun || run.revision != coordinator.revision else { return }

        let isAppend = isSameRun && run.revision == coordinator.revision + 1
        if !isAppend {
            coordinator.interpreter = ANSIInterpreter()
            storage.setAttributedString(NSAttributedString())
        }
        coordinator.runID = run.id
        coordinator.generation = run.generation
        coordinator.revision = run.revision
        coordinator.interpreter.render(isAppend ? run.delta : run.log, into: storage, font: Self.font)
        if following { textView.scrollToEndOfDocument(nil) }
    }

    private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        return visible.maxY >= documentView.frame.height - Self.tailSlack
    }
}

struct ANSIInterpreter {
    private var colour: NSColor = .labelColor
    private var isBold = false
    private var isDim = false
    private var partial = ""

    mutating func render(_ text: String, into storage: NSTextStorage, font: NSFont) {
        var run = ""
        var characters = Array(partial + text)[...]
        partial = ""

        func flush() {
            guard !run.isEmpty else { return }
            storage.append(NSAttributedString(string: run, attributes: attributes(font)))
            run = ""
        }

        while let character = characters.first {
            characters = characters.dropFirst()
            switch character {
            case "\u{1B}":
                guard let sequence = Self.take(&characters) else {
                    partial = "\u{1B}" + String(characters)
                    characters = characters.prefix(0)
                    continue
                }
                flush()
                apply(sequence)
            case "\r":
                flush()
                rewindLine(in: storage)
            default:
                run.append(character)
            }
        }
        flush()
    }

    private func attributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        let face = isBold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        return [.font: face, .foregroundColor: isDim ? colour.withAlphaComponent(0.6) : colour]
    }

    private static func take(_ characters: inout ArraySlice<Character>) -> String? {
        guard let introducer = characters.first else { return nil }
        characters = characters.dropFirst()
        guard introducer == "[" else {
            while let character = characters.first, character != "\u{07}", character != "\u{1B}" {
                characters = characters.dropFirst()
            }
            return ""
        }
        var body = ""
        while let character = characters.first {
            characters = characters.dropFirst()
            body.append(character)
            if character.isLetter { return body }
        }
        return nil
    }

    private mutating func apply(_ sequence: String) {
        guard sequence.hasSuffix("m") else { return }
        let codes = sequence.dropLast().split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var index = 0
        while index < max(codes.count, 1) {
            let code = codes.isEmpty ? 0 : codes[index]
            switch code {
            case 0: colour = .labelColor; isBold = false; isDim = false
            case 1: isBold = true
            case 2: isDim = true
            case 22: isBold = false; isDim = false
            case 30...37: colour = Self.palette[code - 30]
            case 90...97: colour = Self.palette[code - 90]
            case 39: colour = .labelColor
            case 38, 48: index += codes.count > index + 1 && codes[index + 1] == 5 ? 2 : 4
            default: break
            }
            index += 1
        }
    }

    private func rewindLine(in storage: NSTextStorage) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let lineStart = text.range(
            of: "\n", options: .backwards, range: NSRange(location: 0, length: text.length))
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        guard start < text.length else { return }
        storage.deleteCharacters(in: NSRange(location: start, length: text.length - start))
    }

    private static let palette: [NSColor] = [
        .secondaryLabelColor, .systemRed, .systemGreen, .systemOrange,
        .systemBlue, .systemPurple, .systemTeal, .labelColor
    ]
}
