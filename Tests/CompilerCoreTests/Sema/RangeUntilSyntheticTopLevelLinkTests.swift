@testable import CompilerCore
import Foundation
import XCTest

final class RangeUntilSyntheticTopLevelLinkTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    private func assertOpenEndRange(
        _ type: TypeID,
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .classType(classType) = sema.types.kind(of: type),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            XCTFail("Expected OpenEndRange class type, got \(sema.types.renderType(type))", file: file, line: line)
            return
        }
        XCTAssertEqual(interner.resolve(symbol.name), "OpenEndRange", file: file, line: line)
        XCTAssertEqual(classType.args.count, 1, file: file, line: line)
        guard let argument = classType.args.first else {
            return
        }
        switch argument {
        case let .invariant(actual), let .out(actual), let .in(actual):
            XCTAssertEqual(actual, elementType, file: file, line: line)
        case .star:
            XCTFail("Expected concrete OpenEndRange type argument", file: file, line: line)
        }
    }

    func testRangeUntilOperatorSurfaceReturnsOpenEndRange() throws {
        let (sema, interner) = try makeSema()
        let rangeUntilFQName = ["kotlin", "ranges", "rangeUntil"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: rangeUntilFQName)

        XCTAssertEqual(candidates.count, 1, "rangeUntil should register the generic OpenEndRange-returning operator")
        let rangeUntilSymbol = try XCTUnwrap(candidates.first)
        let symbol = try XCTUnwrap(sema.symbols.symbol(rangeUntilSymbol))
        XCTAssertTrue(symbol.flags.contains(.operatorFunction))
        XCTAssertEqual(sema.symbols.externalLinkName(for: rangeUntilSymbol), "kk_op_rangeUntil")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: rangeUntilSymbol))
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        XCTAssertEqual(signature.receiverType, typeParameterType)
        XCTAssertEqual(signature.parameterTypes, [typeParameterType])
        try assertOpenEndRange(
            signature.returnType,
            elementType: typeParameterType,
            sema: sema,
            interner: interner
        )
    }

    func testRangeUntilCallReturnsOpenEndRangeAndEndExclusiveResolves() throws {
        let source = """
        fun sample(): Int {
            val range = 0.rangeUntil(10)
            return range.endExclusive
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "rangeUntil should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let rangeUntilCalls = memberCallExprIDs(named: "rangeUntil", in: ast, interner: interner)
            XCTAssertEqual(rangeUntilCalls.count, 1)
            let rangeUntilCall = try XCTUnwrap(rangeUntilCalls.first)
            let rangeUntilType = try XCTUnwrap(sema.bindings.exprType(for: rangeUntilCall))
            try assertOpenEndRange(
                rangeUntilType,
                elementType: sema.types.intType,
                sema: sema,
                interner: interner
            )
            XCTAssertTrue(sema.bindings.isRangeExpr(rangeUntilCall))

            let endExclusiveCalls = memberCallExprIDs(named: "endExclusive", in: ast, interner: interner)
            XCTAssertEqual(endExclusiveCalls.count, 1)
            if let endExclusiveCall = endExclusiveCalls.first {
                XCTAssertEqual(sema.bindings.exprType(for: endExclusiveCall), sema.types.intType)
            }
        }
    }

    func testRangeUntilOverloadMatrixIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let untilFQName = ["kotlin", "ranges", "until"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: untilFQName)

        XCTAssertEqual(candidates.count, 4, "until should register four signed overloads")

        let expectedSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = [
            (sema.types.intType, sema.types.intType, sema.types.intType),
            (sema.types.intType, sema.types.longType, sema.types.longType),
            (sema.types.longType, sema.types.intType, sema.types.longType),
            (sema.types.longType, sema.types.longType, sema.types.longType),
        ]

        for expected in expectedSignatures {
            XCTAssertTrue(
                candidates.contains(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == expected.receiver
                        && signature.parameterTypes == [expected.parameter]
                        && signature.returnType == expected.returnType
                }),
                "Missing until overload receiver=\(sema.types.renderType(expected.receiver)), parameter=\(sema.types.renderType(expected.parameter))"
            )
        }

        let links = Set(candidates.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertEqual(links, Set(["kk_op_rangeUntil"]), "All until overloads should link to kk_op_rangeUntil")
    }

    func testMixedWidthUntilCallsResolveAndRemainRangeExpressions() throws {
        let source = """
        fun sample(): Int {
            val bb = 1.toByte() until 2.toByte()
            val ss = 1.toShort() until 2.toShort()
            val bl = 1.toByte() until 2L
            val lb = 1L until 2.toShort()
            val ll = 1L until 2L
            return bb.count() + ss.count() + bl.count() + lb.count() + ll.count()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "until calls should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let untilCalls = memberCallExprIDs(named: "until", in: ast, interner: interner)
            XCTAssertEqual(untilCalls.count, 5, "Expected five until calls in the sample")

            let expectedUntilSignatures: [(receiver: TypeID, parameter: TypeID, returnType: TypeID)] = [
                (sema.types.intType, sema.types.intType, sema.types.intType),
                (sema.types.intType, sema.types.intType, sema.types.intType),
                (sema.types.intType, sema.types.longType, sema.types.longType),
                (sema.types.longType, sema.types.intType, sema.types.longType),
                (sema.types.longType, sema.types.longType, sema.types.longType),
            ]

            for (index, callExprID) in untilCalls.enumerated() {
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected a chosen callee for until call at index \(index)"
                )
                let signature = try XCTUnwrap(
                    sema.symbols.functionSignature(for: chosenCallee),
                    "Expected a function signature for until call at index \(index)"
                )
                let expected = expectedUntilSignatures[index]
                XCTAssertEqual(
                    signature.receiverType,
                    expected.receiver,
                    "Unexpected until receiver type at index \(index)"
                )
                XCTAssertEqual(
                    signature.parameterTypes,
                    [expected.parameter],
                    "Unexpected until parameter type at index \(index)"
                )
                XCTAssertEqual(
                    signature.returnType,
                    expected.returnType,
                    "Unexpected until return type at index \(index)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    "kk_op_rangeUntil",
                    "until should lower to kk_op_rangeUntil"
                )
                XCTAssertTrue(
                    sema.bindings.isRangeExpr(callExprID),
                    "until call at index \(index) should be marked as a range expression"
                )
            }

            let countCalls = memberCallExprIDs(named: "count", in: ast, interner: interner)
            XCTAssertEqual(countCalls.count, 5, "Expected five count calls in the sample")
            for (index, countCallID) in countCalls.enumerated() {
                XCTAssertEqual(
                    sema.bindings.exprTypes[countCallID],
                    sema.types.intType,
                    "count() should infer Int at index \(index)"
                )
                if case let .memberCall(receiverExprID, _, _, _, _) = ast.arena.expr(countCallID) {
                    XCTAssertTrue(
                        sema.bindings.isRangeExpr(receiverExprID),
                        "count() receiver at index \(index) should remain marked as a range"
                    )
                } else {
                    XCTFail("Expected a memberCall expression for count at index \(index)")
                }
            }
        }
    }
}
