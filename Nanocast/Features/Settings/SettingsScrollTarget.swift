import SwiftUI

extension View {
    func settingsScrollTarget(_ tab: SettingsTab) -> some View {
        modifier(SettingsScrollTarget(tab: tab))
    }

    func settingsAnchor(_ anchor: SettingsAnchor) -> some View {
        id(SettingsTarget.section(anchor))
    }
}

private struct SearchPill: ViewModifier {
    let target: SettingsTarget
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(
                Capsule().fill(navigation.flashing == target ? Theme.Colors.searchFlash : .clear)
            )
            .padding(.horizontal, -Theme.Spacing.sm)
            .padding(.vertical, -Theme.Spacing.xxs)
            .id(target)
    }
}

struct SettingsSectionHeader<Label: View>: View {
    let anchor: SettingsAnchor
    @ViewBuilder var label: Label

    var body: some View {
        label.modifier(SearchPill(target: .section(anchor)))
    }
}

extension SettingsSectionHeader where Label == Text {
    init(_ anchor: SettingsAnchor) {
        self.init(anchor: anchor) { Text(anchor.title) }
    }
}

struct SettingsRowTitle: View {
    let anchor: SettingsAnchor
    let title: String

    init(_ anchor: SettingsAnchor, _ title: String) {
        self.anchor = anchor
        self.title = title
    }

    var body: some View {
        Text(title).modifier(SearchPill(target: .row(anchor, title)))
    }
}

private struct SettingsScrollTarget: ViewModifier {
    let tab: SettingsTab
    @Environment(SettingsNavigationState.self) private var navigation

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: navigation.scrollRequest) { await reveal(with: proxy) }
        }
    }

    private func reveal(with proxy: ScrollViewProxy) async {
        guard let request = navigation.scrollRequest, request.target.tab == tab else { return }
        await Task.yield()
        withAnimation(.easeOut(duration: Theme.Duration.settingsReveal)) {
            proxy.scrollTo(request.target, anchor: .center)
        }
        navigation.beginFlash(request.target)
        do {
            try await Task.sleep(for: .seconds(Theme.Duration.settingsFlash))
        } catch {
            return
        }
        withAnimation(.easeOut(duration: Theme.Duration.settingsFlashOut)) {
            navigation.endFlash(request.target)
        }
        navigation.clear(request)
    }
}
