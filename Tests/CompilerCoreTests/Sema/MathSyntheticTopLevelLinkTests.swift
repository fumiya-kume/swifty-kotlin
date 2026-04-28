@testable import CompilerCore
import Foundation
import XCTest

final class MathSyntheticTopLevelLinkTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "math", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func mathExtensionProperty(
        named member: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (property: SymbolID, getter: SymbolID)? {
        let fq = ["kotlin", "math", member].map { interner.intern($0) }
        for symbolID in sema.symbols.lookupAll(fqName: fq) {
            guard sema.symbols.symbol(symbolID)?.kind == .property,
                  sema.symbols.extensionPropertyReceiverType(for: symbolID) == receiverType,
                  let getter = sema.symbols.extensionPropertyGetterAccessor(for: symbolID)
            else {
                continue
            }
            return (symbolID, getter)
        }
        return nil
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

    // STDLIB-500..509: Float overloads resolve alongside Double overloads
    func testFloatMathOverloadsHaveExternalLinks() throws {
        let (sema, interner) = try makeSema()

        // Each of these names should have at least two overloads registered
        // (Double and Float). Verify the Float variant has a link name.
        let floatOverloads: [(String, String)] = [
            ("sin", "kk_math_sin_float"),
            ("cos", "kk_math_cos_float"),
            ("tan", "kk_math_tan_float"),
            ("asin", "kk_math_asin_float"),
            ("acos", "kk_math_acos_float"),
            ("atan", "kk_math_atan_float"),
            ("atan2", "kk_math_atan2_float"),
            ("sqrt", "kk_math_sqrt_float"),
            ("round", "kk_math_round_float"),
            ("ceil", "kk_math_ceil_float"),
            ("floor", "kk_math_floor_float"),
            ("abs", "kk_math_abs_float"),
            ("exp", "kk_math_exp_float"),
            ("expm1", "kk_math_expm1_float"),
            ("ln", "kk_math_ln_float"),
            ("ln1p", "kk_math_ln1p_float"),
            ("log2", "kk_math_log2_float"),
            ("log10", "kk_math_log10_float"),
            ("log", "kk_math_log_float"),
            ("sign", "kk_math_sign_float"),
            ("hypot", "kk_math_hypot_float"),
        ]

        for (name, expectedLink) in floatOverloads {
            let fq = ["kotlin", "math", name].map { interner.intern($0) }
            let allSymbols = sema.symbols.lookupAll(fqName: fq)
            let hasFloatLink = allSymbols.contains { sym in
                sema.symbols.externalLinkName(for: sym) == expectedLink
            }
            XCTAssertTrue(
                hasFloatLink,
                "Float overload for \(name) should link to \(expectedLink)"
            )
        }
    }

    func testMathTopLevelCallsResolveWithKotlinMathImport() throws {
        let source = """
        import kotlin.math.*

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

    func testFloatingPrecisionHelpersResolveWithKotlinMathImport() throws {
        let source = """
        import kotlin.math.*

        fun sample(x: Double, y: Float) {
            val a = ulp(x)
            val b = nextUp(x)
            val c = nextDown(x)
            val d = ulp(y)
            val e = nextUp(y)
            val f = nextDown(y)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let expectedLinks = [
                "kk_double_ulp",
                "kk_double_nextUp",
                "kk_double_nextDown",
                "kk_float_ulp",
                "kk_float_nextUp",
                "kk_float_nextDown",
            ]

            var resolvedLinks: [String] = []
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { continue }
                let name = ctx.interner.resolve(calleeName)
                guard ["ulp", "nextUp", "nextDown"].contains(name),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else { continue }
                resolvedLinks.append(link)
            }

            for expected in expectedLinks {
                XCTAssertTrue(resolvedLinks.contains(expected), "Expected \(expected) to be resolved")
            }
        }
    }

    func testMathExtensionPropertySymbolsUseOfficialShape() throws {
        let (sema, interner) = try makeSema()
        let expected: [(String, TypeID, TypeID, String)] = [
            ("absoluteValue", sema.types.doubleType, sema.types.doubleType, "kk_math_abs"),
            ("absoluteValue", sema.types.floatType, sema.types.floatType, "kk_math_abs_float"),
            ("absoluteValue", sema.types.intType, sema.types.intType, "kk_math_abs_int"),
            ("absoluteValue", sema.types.longType, sema.types.longType, "kk_math_abs_long"),
            ("sign", sema.types.doubleType, sema.types.doubleType, "kk_math_sign"),
            ("sign", sema.types.floatType, sema.types.floatType, "kk_math_sign_float"),
            ("sign", sema.types.intType, sema.types.intType, "kk_math_sign_int"),
            ("sign", sema.types.longType, sema.types.intType, "kk_math_sign_long"),
            ("ulp", sema.types.doubleType, sema.types.doubleType, "kk_double_ulp"),
            ("ulp", sema.types.floatType, sema.types.floatType, "kk_float_ulp"),
        ]

        for (name, receiverType, returnType, expectedLink) in expected {
            let symbols = try XCTUnwrap(
                mathExtensionProperty(named: name, receiverType: receiverType, sema: sema, interner: interner),
                "Expected \(name) extension property for \(sema.types.renderType(receiverType))"
            )
            XCTAssertEqual(sema.symbols.propertyType(for: symbols.property), returnType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbols.property), expectedLink)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbols.getter), expectedLink)
            let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: symbols.getter))
            XCTAssertEqual(getterSignature.receiverType, receiverType)
            XCTAssertEqual(getterSignature.parameterTypes, [])
            XCTAssertEqual(getterSignature.returnType, returnType)
        }
    }

    func testMathExtensionPropertiesResolveWithKotlinMathImport() throws {
        let source = """
        import kotlin.math.*

        fun sample(i: Int, l: Long, f: Float, d: Double) {
            val ai = i.absoluteValue
            val al = l.absoluteValue
            val af = f.absoluteValue
            val ad = d.absoluteValue
            val si = i.sign
            val sl = l.sign
            val sf = f.sign
            val sd = d.sign
            val uf = f.ulp
            val ud = d.ulp
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError, "Expected math extension properties to resolve without diagnostics.")
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let propertyNames: Set<String> = ["absoluteValue", "sign", "ulp"]
            var resolvedLinks: [String] = []
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, calleeName, _, _, _) = expr,
                      propertyNames.contains(ctx.interner.resolve(calleeName)),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else {
                    continue
                }
                resolvedLinks.append(link)
            }

            for expectedLink in [
                "kk_math_abs_int",
                "kk_math_abs_long",
                "kk_math_abs_float",
                "kk_math_abs",
                "kk_math_sign_int",
                "kk_math_sign_long",
                "kk_math_sign_float",
                "kk_math_sign",
                "kk_float_ulp",
                "kk_double_ulp",
            ] {
                XCTAssertTrue(resolvedLinks.contains(expectedLink), "Expected \(expectedLink), got \(resolvedLinks)")
            }
        }
    }

    func testDoublePowMemberCallResolvesViaMathExtensionStub() throws {
        let source = """
        import kotlin.math.*

        fun sample(): Double {
            return 2.0.pow(3.0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected Double.pow member call to resolve without diagnostics.")

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "pow"
                },
                "Expected pow member call expression"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected chosen callee for Double.pow"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_math_pow"
            )
        }
    }

    func testRemainingFloatingMathMemberCallsResolveViaDefaultImport() throws {
        let source = """
        import kotlin.math.*

        fun sample(d: Double, f: Float, i: Int) {
            val ieeeD = d.IEEErem(d)
            val ieeeF = f.IEEErem(f)
            val nextD = d.nextTowards(d)
            val nextF = f.nextTowards(f)
            val powF = f.pow(f)
            val powDI = d.pow(i)
            val powFI = f.pow(i)
            val signD = d.withSign(d)
            val signDI = d.withSign(i)
            val signF = f.withSign(f)
            val signFI = f.withSign(i)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected remaining math member calls to resolve without diagnostics.")

            var resolvedLinks: [String] = []
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, calleeName, _, _, _) = expr,
                      ["IEEErem", "nextTowards", "pow", "withSign"].contains(ctx.interner.resolve(calleeName)),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else {
                    continue
                }
                resolvedLinks.append(link)
            }

            for expectedLink in [
                "kk_math_IEEErem",
                "kk_math_IEEErem_float",
                "kk_math_nextTowards",
                "kk_math_nextTowards_float",
                "kk_math_pow_float",
                "kk_math_pow_int",
                "kk_math_pow_float_int",
                "kk_math_withSign",
                "kk_math_withSign_int",
                "kk_math_withSign_float",
                "kk_math_withSign_float_int",
            ] {
                XCTAssertTrue(resolvedLinks.contains(expectedLink), "Expected \(expectedLink), got \(resolvedLinks)")
            }
        }
    }
}
