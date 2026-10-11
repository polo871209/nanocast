import AppKit
import SwiftUI

struct UpdateWindowView: View {
    @Environment(UpdateCoordinator.self) private var updates

    static let width: CGFloat = 460
    static let initialSize = CGSize(width: width, height: 158)

    private static let iconSize: CGFloat = 52
    /// macOS bakes a transparent margin into an app icon; bleeding it out aligns the artwork.
    private static let iconBleed: CGFloat = 6
    private static let cardHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            hero
            detail
            actions
        }
        .padding(.top, Theme.Spacing.sm)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            updates.fit(height: $0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear], startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: Self.iconSize + Self.iconBleed * 2,
                    height: Self.iconSize + Self.iconBleed * 2
                )
                .padding(-Self.iconBleed)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch updates.stage {
        case .checking: return "Checking for updates…"
        case .upToDate: return "\(Bundle.main.appDisplayName) is up to date"
        case .localBuild:
            return "\(Bundle.main.appDisplayName) doesn't update itself"
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return "\(Bundle.main.appDisplayName) \(release.version.description) is available"
        case .readyToRelaunch: return "Update installed"
        case .failed: return "Update failed"
        }
    }

    private var subtitle: String {
        switch updates.stage {
        case .checking, .upToDate, .failed:
            return "Version \(updates.runningVersion)"
        case .localBuild:
            return "This is a local build — rebuild it to move it forward."
        case .available, .blocked, .installing:
            return "You have \(updates.runningVersion)."
        case .readyToRelaunch:
            return "Relaunch to start using it."
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch updates.stage {
        case .checking, .upToDate, .localBuild, .readyToRelaunch:
            EmptyView()
        case .available(let release):
            card { notes(release) }
        case .blocked(let blocker, _):
            Label(blocker.message, systemImage: "clock")
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .installing(_, let phase):
            progress(phase)
        case .failed(let failure):
            card { report(failure) }
        }
    }

    private func notes(_ release: AvailableRelease) -> some View {
        ReleaseNotesView(text: release.notes)
    }

    private func report(_ failure: UpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(failure.errorDescription ?? "Something went wrong.")
                .font(.callout)
            if let recovery = failure.recoverySuggestion {
                Text(recovery)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ phase: UpdateInstaller.Phase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let fraction = phase.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(phase.message)
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            content()
                .textSelection(.enabled)
                .padding(Theme.Spacing.xl)
        }
        .frame(height: Self.cardHeight)
        .background(Theme.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            switch updates.stage {
            case .checking:
                ProgressView().controlSize(.small)
                Button("Cancel") { updates.dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .upToDate, .localBuild:
                Button("OK") { updates.dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .available:
                Button("Later") { updates.skip() }
                    .keyboardShortcut(.cancelAction)
                Button("Update Now") { updates.install() }
                    .keyboardShortcut(.defaultAction)
            case .blocked:
                Button("Later") { updates.skip() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { updates.retry() }
                    .keyboardShortcut(.defaultAction)
            case .installing:
                Button("Cancel") { updates.cancelInstall() }
                    .keyboardShortcut(.cancelAction)
            case .readyToRelaunch:
                Button("Later") { updates.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Relaunch") { updates.relaunch() }
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Close") { updates.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
