enum WindowSwitchEligibility {
    /// Zen reports its main window as `AXDialog` at times. A sheet cannot minimize.
    static func isSwitchable(
        isStandard: Bool, isDialog: Bool, isMinimized: Bool, canMinimize: @autoclosure () -> Bool
    ) -> Bool {
        guard !isMinimized else { return false }
        return isStandard || (isDialog && canMinimize())
    }
}
