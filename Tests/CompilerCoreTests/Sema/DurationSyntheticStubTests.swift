@testable import CompilerCore
import XCTest

final class DurationSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testDurationOperatorMembersAreRegisteredWithReceiverType() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let expectedMembers: [(name: String, link: String, parameterTypes: [TypeID], canThrow: Bool)] = [
            ("plus", "kk_duration_plus", [durationType], false),
            ("minus", "kk_duration_minus", [durationType], false),
            ("times", "kk_duration_times_int", [sema.types.intType], false),
            ("times", "kk_duration_times_double", [sema.types.doubleType], true),
            ("div", "kk_duration_div_int", [sema.types.intType], false),
            ("div", "kk_duration_div_double", [sema.types.doubleType], true),
            ("div", "kk_duration_div_duration", [durationType], false),
            ("compareTo", "kk_duration_compareTo", [durationType], false),
            ("unaryMinus", "kk_duration_unary_minus", [], false),
        ]

        for member in expectedMembers {
            let memberFQName = durationFQName + [interner.intern(member.name)]
            let matchingSymbols = sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == durationType
                    && signature.parameterTypes == member.parameterTypes
            }

            XCTAssertEqual(
                matchingSymbols.count,
                1,
                "Expected exactly one Duration.\(member.name) overload with receiverType=Duration"
            )
            let symbol = try XCTUnwrap(matchingSymbols.first)
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
            XCTAssertTrue(
                sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true,
                "Duration.\(member.name) should be an operatorFunction"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), member.link)
            XCTAssertEqual(
                sema.symbols.functionSignature(for: symbol)?.canThrow,
                member.canThrow,
                "Duration.\(member.name) throwing flag should match runtime ABI"
            )
        }
    }

    func testDurationDoubleScaleOperatorsResolveInSource() throws {
        let source = """
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val base: Duration = 3.seconds
            val multiplied: Duration = base * 2.5
            val divided: Duration = base / 2.0
            println(multiplied)
            println(divided)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Duration Double scale operators should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testDurationIsoAndParseSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let toIsoFQName = durationFQName + [interner.intern("toIsoString")]
        let toIsoSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toIsoFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == durationType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: toIsoSymbol), "kk_duration_toIsoString")
        XCTAssertFalse(
            sema.symbols.symbol(toIsoSymbol)?.flags.contains(.operatorFunction) == true,
            "Duration.toIsoString should not be registered as an operator"
        )

        let companionFQName = durationFQName + [interner.intern("Companion")]
        let parseFQName = companionFQName + [interner.intern("parse")]
        let parseSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == durationType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseSymbol), "kk_duration_parse")
        XCTAssertTrue(
            sema.symbols.symbol(parseSymbol)?.flags.contains(.throwingFunction) == true,
            "Duration.parse should use the thrown channel for invalid input"
        )

        let parseOrNullFQName = companionFQName + [interner.intern("parseOrNull")]
        let parseOrNullSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseOrNullFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.makeNullable(durationType)
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseOrNullSymbol), "kk_duration_parseOrNull")

        let parseIsoFQName = companionFQName + [interner.intern("parseIsoString")]
        let parseIsoSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseIsoFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == durationType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseIsoSymbol), "kk_duration_parseIsoString")
        XCTAssertTrue(
            sema.symbols.symbol(parseIsoSymbol)?.flags.contains(.throwingFunction) == true,
            "Duration.parseIsoString should use the thrown channel for invalid input"
        )

        let parseIsoOrNullFQName = companionFQName + [interner.intern("parseIsoStringOrNull")]
        let parseIsoOrNullSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseIsoOrNullFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.makeNullable(durationType)
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseIsoOrNullSymbol), "kk_duration_parseIsoStringOrNull")
    }

    func testDurationToComponentsOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let toComponentsFQName = durationFQName + [interner.intern("toComponents")]
        let overloads: [(link: String, params: [TypeID])] = [
            ("kk_duration_toComponents_seconds", [sema.types.longType, sema.types.intType]),
            ("kk_duration_toComponents_minutes", [sema.types.longType, sema.types.intType, sema.types.intType]),
            (
                "kk_duration_toComponents_hours",
                [sema.types.longType, sema.types.intType, sema.types.intType, sema.types.intType]
            ),
            (
                "kk_duration_toComponents_days",
                [
                    sema.types.longType,
                    sema.types.intType,
                    sema.types.intType,
                    sema.types.intType,
                    sema.types.intType,
                ]
            ),
        ]

        for overload in overloads {
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toComponentsFQName).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == overload.link
            })
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.receiverType, durationType)
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.returnType, sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0]
            ))))
            XCTAssertTrue(
                sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true,
                "Duration.toComponents should be registered as inline synthetic surface"
            )
            guard let actionType = signature.parameterTypes.first,
                  case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(actionType))
            else {
                return XCTFail("Duration.toComponents action must be a function type")
            }
            XCTAssertEqual(functionType.params, overload.params)
            XCTAssertEqual(functionType.returnType, signature.returnType)
        }
    }

    func testNumericToDurationExtensionsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let durationUnitFQName = ["kotlin", "time", "DurationUnit"].map { interner.intern($0) }
        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationUnitFQName))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))

        let toDurationFQName = ["kotlin", "time", "toDuration"].map { interner.intern($0) }
        let expected: [(receiver: TypeID, link: String)] = [
            (sema.types.intType, "kk_duration_toDuration_int"),
            (sema.types.longType, "kk_duration_toDuration_long"),
            (sema.types.doubleType, "kk_duration_toDuration_double"),
        ]

        for overload in expected {
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toDurationFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == overload.receiver
                    && signature.parameterTypes == [durationUnitType]
                    && signature.returnType == durationType
            })
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), overload.link)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.valueParameterSymbols.count, 1)
            XCTAssertEqual(
                sema.symbols.propertyType(for: signature.valueParameterSymbols[0]),
                durationUnitType
            )
        }
    }
}
