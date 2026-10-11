import CoreServices
import Darwin
import Foundation

enum DictionaryService {
    nonisolated static func entry(for term: String) -> DictionaryEntry? {
        if let blocks = DictionaryRecords.resolved?.blocks(for: term) {
            return DictionaryEntry(term: term, blocks: blocks)
        }
        return plainText(for: term).map { DictionaryEntry(term: term, plainText: $0) }
    }

    private nonisolated static func plainText(for term: String) -> String? {
        let range = CFRange(location: 0, length: term.utf16.count)
        guard let text = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue()
        else { return nil }
        let trimmed = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Dictionary Services' record calls: what Dictionary.app reads, though no header declares them.
private struct DictionaryRecords: Sendable {
    private typealias ActiveDictionaries = @convention(c) () -> Unmanaged<CFArray>?
    private typealias CopyRecords =
        @convention(c) (
            DCSDictionary, CFString, UnsafeRawPointer?, UnsafeRawPointer?
        ) -> Unmanaged<CFArray>?
    private typealias CopyData = @convention(c) (CFTypeRef, CFIndex) -> Unmanaged<CFString>?

    private static let xhtml: CFIndex = 0

    private let activeDictionaries: ActiveDictionaries
    private let copyRecords: CopyRecords
    private let copyData: CopyData

    static let resolved: DictionaryRecords? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let active = dlsym(rtldDefault, "DCSGetActiveDictionaries"),
            let records = dlsym(rtldDefault, "DCSCopyRecordsForSearchString"),
            let data = dlsym(rtldDefault, "DCSRecordCopyData")
        else { return nil }
        return DictionaryRecords(
            activeDictionaries: unsafeBitCast(active, to: ActiveDictionaries.self),
            copyRecords: unsafeBitCast(records, to: CopyRecords.self),
            copyData: unsafeBitCast(data, to: CopyData.self))
    }()

    func blocks(for term: String) -> [DictionaryEntry.Block]? {
        guard let dictionaries = activeDictionaries()?.takeUnretainedValue() as? [DCSDictionary]
        else { return nil }
        for dictionary in dictionaries {
            guard
                let records = copyRecords(dictionary, term as CFString, nil, nil)?
                    .takeRetainedValue() as? [CFTypeRef]
            else { continue }
            let blocks = records.flatMap { record in
                (copyData(record, Self.xhtml)?.takeRetainedValue() as String?)
                    .map(DictionaryMarkup.blocks(fromXHTML:)) ?? []
            }
            if !blocks.isEmpty { return blocks }
        }
        return nil
    }
}
