import SwiftUI

private struct InterfaceMetricsScope: ViewModifier {
    let settings: AppSettings

    func body(content: Content) -> some View {
        content.environment(\.metrics, settings.interfaceSize.metrics)
    }
}

extension View {
    func paletteEnvironment(_ core: AppCore) -> some View {
        self
            .modifier(InterfaceMetricsScope(settings: core.settings))
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.appIndex)
            .environment(core.clipboardStore)
            .environment(core.favorites)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.calcHistory)
            .environment(core.currencyRates)
            .environment(core.emojiIndex)
            .environment(core.frequentEmoji)
            .environment(core.fileSearch)
            .environment(core.dictionary)
            .environment(core.menuSearch)
            .environment(core.runningApps)
            .environment(core.hotKeys)
            .environment(core.uninstall)
    }
}
