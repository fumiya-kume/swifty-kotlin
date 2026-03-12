import Foundation

public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast, let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }

        let loweringCtx = KIRLoweringContext()
        let driver = KIRLoweringDriver(ctx: loweringCtx)
        let module = driver.lowerModule(ast: ast, sema: sema, compilationCtx: ctx)

        if module.functionCount == 0, !ctx.diagnostics.hasError {
            ctx.diagnostics.warning(
                "KSWIFTK-KIR-0001",
                "No function declarations found.",
                range: nil
            )
        }
        ctx.storeKIR(module)
    }
}
