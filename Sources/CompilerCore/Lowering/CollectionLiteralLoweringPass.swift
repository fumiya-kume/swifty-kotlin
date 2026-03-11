import Foundation

final class CollectionLiteralLoweringPass: LoweringPass {
    static let name = "CollectionLiteralLowering"

    func run(module: KIRModule, ctx: KIRContext) throws {
        try rewriteCalls(module: module, ctx: ctx)
    }
}
