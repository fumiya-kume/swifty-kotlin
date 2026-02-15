import Foundation

final class ForLoweringPass: LoweringPass {
    static let name = "ForLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        _ = ctx
        _ = module
        module.recordLowering(Self.name)
    }
}
