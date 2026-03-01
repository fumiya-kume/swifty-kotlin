@testable import CompilerCore
import XCTest

/// Type token symbols use this negative offset to avoid collision with real symbol IDs.
let typeTokenSymbolOffset: Int = -20000

/// Coroutine state machine dispatch labels start at this offset.
let coroutineDispatchLabelBase: Int32 = 1000

func findKIRFunction(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> KIRFunction {
    let function = module.arena.declarations.compactMap { decl -> KIRFunction? in
        guard case let .function(function) = decl else { return nil }
        return interner.resolve(function.name) == name ? function : nil
    }.first
    return try XCTUnwrap(function, "KIR function '\(name)' not found in module", file: file, line: line)
}

func findKIRFunctionBody(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [KIRInstruction] {
    let function = try findKIRFunction(named: name, in: module, interner: interner, file: file, line: line)
    return function.body
}

func extractCallees(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String] {
    body.compactMap { instruction -> String? in
        guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
        return interner.resolve(callee)
    }
}

func extractThrowFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String: [Bool]] {
    body.reduce(into: [:]) { partial, instruction in
        guard case let .call(_, callee, _, _, canThrow, _, _) = instruction else { return }
        partial[interner.resolve(callee), default: []].append(canThrow)
    }
}

func firstExprID(
    in ast: ASTModule,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID) else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}

func llvmCapiBindingsAvailable() -> Bool {
    guard let bindings = LLVMCAPIBindings.load() else { return false }
    return bindings.smokeTestContextLifecycle()
}
