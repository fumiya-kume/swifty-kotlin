
final class ExprLowerer {
    unowned let driver: KIRLoweringDriver
    private var lambdaCapturedSymbols: Set<SymbolID>?

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func isCapturedByLambda(_ symbol: SymbolID, sema: SemaModule) -> Bool {
        // Sema has completed before this lowering session starts. Cache its
        // capture union once instead of rescanning every lambda for each local.
        if lambdaCapturedSymbols == nil {
            lambdaCapturedSymbols = Set(sema.bindings.captureSymbolsByExpr.values.joined())
        }
        return lambdaCapturedSymbols?.contains(symbol) == true
    }
}
