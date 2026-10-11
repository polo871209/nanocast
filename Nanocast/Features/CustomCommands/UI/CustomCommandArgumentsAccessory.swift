import SwiftUI

@MainActor
enum CustomCommandArgumentsAccessory {
    static func make(
        command: CustomCommand?,
        vm: PaletteState,
        metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let command, !command.arguments.isEmpty else { return nil }
        let arguments = command.arguments.enumerated().map { index, argument in
            InlineArgument(
                id: CustomCommandArgument.fieldID(at: index), title: argument.name,
                isOptional: argument.isOptional)
        }
        let value = { (id: String) in binding(command: command, id: id, vm: vm) }
        let firstOwed = {
            arguments.first { !$0.isOptional && value($0.id).wrappedValue.isEmpty }?.id
        }
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: firstOwed(),
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: command.symbol, value: value, focused: focus,
                    openOptions: { _ in },
                    onSubmit: {
                        guard let owed = firstOwed() else { return onSubmit() }
                        focus.wrappedValue = owed
                    }
                )
                .id(command.entryID))
        )
    }

    static func values(for command: CustomCommand, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for index in command.arguments.indices {
            let id = CustomCommandArgument.fieldID(at: index)
            let typed = vm.commandArguments[PaletteState.ArgumentKey(entryID: command.entryID, name: id)] ?? ""
            if !typed.isEmpty { values[id] = typed }
        }
        return values
    }

    private static func binding(
        command: CustomCommand, id: String, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.ArgumentKey(entryID: command.entryID, name: id)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }
}
