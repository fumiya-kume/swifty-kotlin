import Foundation

/// Delegate class for KIR lowering: ExprLowerer.
/// Holds an unowned reference to the driver for mutual recursion.
final class ExprLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }
}
