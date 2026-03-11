@testable import CompilerCore
import Foundation
import XCTest

final class MathSyntheticTopLevelLinkTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "math", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    func testMathTopLevelSymbolsLinkToRuntimeFunctions() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "sqrt": "kk_math_sqrt",
            "pow": "kk_math_pow",
            "ceil": "kk_math_ceil",
            "floor": "kk_math_floor",
            "round": "kk_math_round",
        ]

        for (name, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: name, sema: sema, interner: interner),
                expectedLink,
                "\(name) in kotlin.math should link to runtime"
            )
        }
    }

    func testMathTopLevelCallsResolveViaDefaultImport() throws {
        let source = """
        fun sample(x: Int, y: Double): Double {
            val ai = abs(-x)
            val ad = abs(y)
            return sqrt(ad * ad) + pow(ad, 2.0) + ceil(ad) + floor(ad) + round(ad)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            var absCalls: [ExprID] = []
            var callByName: [String: [ExprID]] = [:]

            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .call(calleeExpr, _, _, _) = expr else { continue }
                guard case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr) else { continue }
                let name = ctx.interner.resolve(calleeName)
                callByName[name, default: []].append(exprID)
                if name == "abs" {
                    absCalls.append(exprID)
                }
            }

            XCTAssertEqual(absCalls.count, 2, "Expected int and double abs calls")

            let expectedOrder: [(String, String)] = [
                ("abs", "kk_math_abs_int"),
                ("abs", "kk_math_abs"),
                ("sqrt", "kk_math_sqrt"),
                ("pow", "kk_math_pow"),
                ("ceil", "kk_math_ceil"),
                ("floor", "kk_math_floor"),
                ("round", "kk_math_round"),
            ]
            var consumedByName: [String: Int] = [:]

            for (index, expected) in expectedOrder.enumerated() {
                let (name, expectedLink) = expected
                let callExpr: ExprID = {
                    if name == "abs" {
                        return absCalls[index == 0 ? 0 : 1]
                    }
                    let selectedIndex = consumedByName[name, default: 0]
                    consumedByName[name] = selectedIndex + 1
                    let candidates = callByName[name] ?? []
                    return candidates[selectedIndex]
                }()

                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected chosen callee for \(name)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLink,
                    "Expected \(name) to resolve"
                )
            }
        }
    }
}
