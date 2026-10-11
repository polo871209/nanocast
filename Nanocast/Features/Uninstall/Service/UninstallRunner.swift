import Foundation

struct UninstallFailedItem: Hashable, Sendable {
    let name: String
    let reason: String
}

struct UninstallReport: Sendable {
    let trashed: [UninstallCandidate]
    let failed: [UninstallFailedItem]

    var trashedCount: Int { trashed.count }
    var freedBytes: Int64 { trashed.reduce(0) { $0 + ($1.size?.bytes ?? 0) } }
    var hasFailures: Bool { !failed.isEmpty }
    var removedBundle: Bool { trashed.contains { $0.evidence == .bundle } }
}

enum UninstallRunner {
    static func moveToTrash(_ candidates: [UninstallCandidate]) async -> UninstallReport {
        let removable = candidates.filter { !$0.isLocked }
        let ordered =
            removable.filter { $0.evidence != .bundle } + removable.filter { $0.evidence == .bundle }

        return await Task.detached(priority: .userInitiated) {
            var trashed: [UninstallCandidate] = []
            var failed: [UninstallFailedItem] = []
            for candidate in ordered {
                do {
                    try FileManager.default.trashItem(at: candidate.url, resultingItemURL: nil)
                    trashed.append(candidate)
                } catch {
                    failed.append(
                        UninstallFailedItem(
                            name: candidate.name, reason: error.localizedDescription))
                }
            }
            return UninstallReport(trashed: trashed, failed: failed)
        }.value
    }
}
