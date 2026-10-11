// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices

enum AXMenuAccess {
    static let sweepTimeout: Float = 0.2
    static let walkBudget: Duration = .seconds(1)

    static func application(for pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, sweepTimeout)
        return application
    }

    static func readTopLevel(
        in application: AXUIElement, deadline: ContinuousClock.Instant
    ) -> [MenuTreeNode] {
        guard let bar = element(application, kAXMenuBarAttribute) else { return [] }
        return readNodes(children(of: bar), deadline: deadline)
    }

    static func resolveLeaf(
        in application: AXUIElement, path: [String], title: String
    ) -> AXUIElement? {
        guard let bar = element(application, kAXMenuBarAttribute) else { return nil }
        return resolve(candidates: children(of: bar), trail: [], path: path, title: title)
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func isActionable(_ element: AXUIElement) -> Bool {
        guard bool(element, kAXEnabledAttribute) != false,
            bool(element, kAXHiddenAttribute) != true
        else { return false }
        return canPress(element)
    }

    private static func readNodes(
        _ candidates: [AXUIElement], deadline: ContinuousClock.Instant
    ) -> [MenuTreeNode] {
        var nodes: [MenuTreeNode] = []
        nodes.reserveCapacity(candidates.count)
        for child in candidates {
            guard ContinuousClock.now < deadline else { return nodes }
            AXUIElementSetMessagingTimeout(child, sweepTimeout)
            let nested = children(of: child)
            let title = string(child, kAXTitleAttribute) ?? ""
            guard !nested.isEmpty else {
                nodes.append(readLeaf(child, title: title))
                continue
            }
            nodes.append(MenuTreeNode(title: title, children: readNodes(nested, deadline: deadline)))
        }
        return nodes
    }

    private static func readLeaf(_ element: AXUIElement, title: String) -> MenuTreeNode {
        let details = batch(element)
        return MenuTreeNode(
            title: title,
            isEnabled: details.enabled ?? true,
            isHidden: details.hidden ?? false,
            canPress: canPress(element),
            shortcut: .commandEquivalent(
                character: details.character ?? "", modifiers: details.modifiers ?? 0),
            children: [])
    }

    private static func batch(
        _ element: AXUIElement
    ) -> (
        enabled: Bool?, hidden: Bool?, character: String?, modifiers: Int?
    ) {
        let names =
            [
                kAXEnabledAttribute, kAXHiddenAttribute, kAXMenuItemCmdCharAttribute,
                kAXMenuItemCmdModifiersAttribute
            ] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
            let values = values as? [Any], values.count == 4
        else {
            return (
                bool(element, kAXEnabledAttribute), bool(element, kAXHiddenAttribute),
                string(element, kAXMenuItemCmdCharAttribute),
                (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
            )
        }
        return (
            values[0] as? Bool, values[1] as? Bool, values[2] as? String,
            (values[3] as? NSNumber)?.intValue
        )
    }

    private static func canPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        return AXUIElementCopyActionNames(element, &actions) == .success
            && (actions as? [String])?.contains(kAXPressAction) == true
    }

    private static func resolve(
        candidates: [AXUIElement], trail: [String], path: [String], title: String
    ) -> AXUIElement? {
        for child in candidates {
            let childTitle = string(child, kAXTitleAttribute) ?? ""
            let nested = children(of: child)
            guard !nested.isEmpty else {
                if trail == path, childTitle == title { return child }
                continue
            }
            var subtrail = trail
            if !childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subtrail.append(childTitle)
            }
            guard subtrail.count <= path.count,
                Array(path.prefix(subtrail.count)) == subtrail,
                let found = resolve(
                    candidates: nested, trail: subtrail, path: path, title: title)
            else { continue }
            return found
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = self.attribute(element, attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        self.attribute(element, attribute) as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        self.attribute(element, attribute) as? Bool
    }

    private static func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
