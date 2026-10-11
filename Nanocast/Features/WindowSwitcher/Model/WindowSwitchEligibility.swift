enum WindowSwitchEligibility {
    /// Zen and hidden apps report main windows as `AXDialog` at times. A sheet cannot minimize.
    static func isSwitchable(
        isStandard: Bool, isDialog: Bool, isMinimized: Bool, isAppHidden: Bool,
        canMinimize: @autoclosure () -> Bool
    ) -> Bool {
        guard !isMinimized else { return false }
        return isStandard || (isDialog && (isAppHidden || canMinimize()))
    }
}
