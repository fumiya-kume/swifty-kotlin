@testable import CompilerCore
import XCTest

final class RangeUntilSyntheticMemberLinkTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func untilSymbols(for sema: SemaModule, interner: StringInterner) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern("until"),
        ])
    }

    private func untilCallExprIDs(in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == "until"
            else {
                return nil
            }
            return exprID
        }
    }

    func testUntilOverloadsHaveExpectedSignaturesAndLinks() throws {
        let (sema, interner) = try makeSema()
        let untilSymbolIDs = untilSymbols(for: sema, interner: interner)

        // Byte and Short collapse to intType internally; mixed Int/Long calls widen to Long.
        let expected: [(receiver: TypeID, parameter: TypeID, returnType: TypeID, link: String)] = [
            (sema.types.intType, sema.types.intType, sema.types.intType, "kk_op_rangeUntil"),
            (sema.types.intType, sema.types.longType, sema.types.longType, "kk_op_rangeUntil"),
            (sema.types.longType, sema.types.intType, sema.types.longType, "kk_op_rangeUntil"),
            (sema.types.longType, sema.types.longType, sema.types.longType, "kk_op_rangeUntil"),
        ]

        for entry in expected {
            let matchingSymbol = untilSymbolIDs.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == entry.receiver
                    && signature.parameterTypes == [entry.parameter]
                    && signature.returnType == entry.returnType
            }
            let symbol = try XCTUnwrap(matchingSymbol, "Expected until stub for \(entry.receiver)")
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: symbol),
                entry.link,
                "Expected \(entry.receiver).until to link to \(entry.link)"
            )
        }
    }

    func testUntilInfixCallsResolveToExpectedRuntimeLinksAndRangeKinds() throws {
        let source = """
        fun sample(b: Byte, s: Short, i: Int, l: Long) {
            val byteRange = b until b
            val shortRange = s until s
            val intRange = i until i
            val intLongRange = i until l
            val longIntRange = l until i
            val longRange = l until l
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let untilCalls = untilCallExprIDs(in: ast, interner: ctx.interner)

        XCTAssertEqual(untilCalls.count, 6)

        let expected: [(type: TypeID, link: String, isUIntRange: Bool, isULongRange: Bool)] = [
            (sema.types.intType, "kk_op_rangeUntil", false, false),
            (sema.types.intType, "kk_op_rangeUntil", false, false),
            (sema.types.intType, "kk_op_rangeUntil", false, false),
            (sema.types.longType, "kk_op_rangeUntil", false, false),
            (sema.types.longType, "kk_op_rangeUntil", false, false),
            (sema.types.longType, "kk_op_rangeUntil", false, false),
        ]

        for (exprID, entry) in zip(untilCalls, expected) {
            let binding = try XCTUnwrap(sema.bindings.callBinding(for: exprID))
            let chosen = binding.chosenCallee
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosen),
                entry.link,
                "Expected until call to resolve to \(entry.link)"
            )
            XCTAssertEqual(
                sema.bindings.exprType(for: exprID),
                entry.type,
                "Unexpected inferred type for until call"
            )
            XCTAssertTrue(sema.bindings.isRangeExpr(exprID), "until should mark a range expression")
            XCTAssertEqual(
                sema.bindings.isUIntRangeExpr(exprID),
                entry.isUIntRange,
                "Unexpected UInt range marker for until call"
            )
            XCTAssertEqual(
                sema.bindings.isULongRangeExpr(exprID),
                entry.isULongRange,
                "Unexpected ULong range marker for until call"
            )
        }
    }
}
