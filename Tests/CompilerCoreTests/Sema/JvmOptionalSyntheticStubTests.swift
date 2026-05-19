@testable import CompilerCore
import Foundation
import XCTest

final class JvmOptionalSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testOptionalGetOrDefaultSignature() throws {
        let (sema, interner) = try makeSema()

        let optionalFQName = ["java", "util", "Optional"].map { interner.intern($0) }
        let optionalSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: optionalFQName),
            "Expected java.util.Optional to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(optionalSymbol)?.kind, .class)

        let classTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: optionalSymbol)
        XCTAssertEqual(classTypeParameterSymbols.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: optionalSymbol), [.invariant])

        let getOrDefaultFQName = ["kotlin", "jvm", "optionals", "getOrDefault"].map { interner.intern($0) }
        let getOrDefaultSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: getOrDefaultFQName),
            "Expected kotlin.jvm.optionals.getOrDefault to be registered"
        )
        let getOrDefaultSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getOrDefaultSymbol))
        XCTAssertTrue(sema.symbols.symbol(getOrDefaultSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertFalse(sema.symbols.symbol(getOrDefaultSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: getOrDefaultSymbol), "kk_optional_getOrDefault")

        let functionTParamSymbol = try XCTUnwrap(getOrDefaultSignature.typeParameterSymbols.first)
        let functionTType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.out(functionTType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(getOrDefaultSignature.receiverType, receiverType)
        XCTAssertEqual(getOrDefaultSignature.parameterTypes, [functionTType])
        XCTAssertEqual(getOrDefaultSignature.returnType, functionTType)
        XCTAssertEqual(getOrDefaultSignature.typeParameterSymbols, [functionTParamSymbol])
        XCTAssertEqual(getOrDefaultSignature.classTypeParameterCount, 0)
    }

    func testOptionalGetOrDefaultResolvesInSource() throws {
        let source = """
        import java.util.Optional
        import kotlin.jvm.optionals.getOrDefault

        fun probe(optional: Optional<String>): String {
            return optional.getOrDefault("fallback")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let getOrDefaultCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "getOrDefault"
            })
            let chosenGetOrDefault = try XCTUnwrap(
                sema.bindings.callBinding(for: getOrDefaultCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenGetOrDefault),
                "kk_optional_getOrDefault"
            )
        }
    }

    func testOptionalToCollectionSignature() throws {
        let (sema, interner) = try makeSema()

        let optionalFQName = ["java", "util", "Optional"].map { interner.intern($0) }
        let optionalSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: optionalFQName),
            "Expected java.util.Optional to be registered"
        )
        let mutableCollectionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "MutableCollection"].map { interner.intern($0) }),
            "Expected kotlin.collections.MutableCollection to be registered"
        )

        let toCollectionFQName = ["kotlin", "jvm", "optionals", "toCollection"].map { interner.intern($0) }
        let toCollectionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: toCollectionFQName),
            "Expected kotlin.jvm.optionals.toCollection to be registered"
        )
        let toCollectionSignature = try XCTUnwrap(sema.symbols.functionSignature(for: toCollectionSymbol))
        XCTAssertTrue(sema.symbols.symbol(toCollectionSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: toCollectionSymbol), "kk_optional_toCollection")

        XCTAssertEqual(toCollectionSignature.typeParameterSymbols.count, 2)
        let tParamSymbol = toCollectionSignature.typeParameterSymbols[0]
        let cParamSymbol = toCollectionSignature.typeParameterSymbols[1]
        let tType = sema.types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let cType = sema.types.make(.typeParam(TypeParamType(
            symbol: cParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.out(tType)],
            nullability: .nonNull
        )))
        let cUpperBound = sema.types.make(.classType(ClassType(
            classSymbol: mutableCollectionSymbol,
            args: [.in(tType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(toCollectionSignature.receiverType, receiverType)
        XCTAssertEqual(toCollectionSignature.parameterTypes, [cType])
        XCTAssertEqual(toCollectionSignature.returnType, cType)
        XCTAssertEqual(toCollectionSignature.typeParameterUpperBoundsList, [[], [cUpperBound]])
        XCTAssertEqual(toCollectionSignature.classTypeParameterCount, 0)
    }

    func testOptionalToCollectionResolvesInSource() throws {
        let source = """
        import java.util.Optional
        import kotlin.collections.MutableCollection
        import kotlin.jvm.optionals.toCollection

        fun probe(optional: Optional<String>, destination: MutableCollection<String>): MutableCollection<String> {
            return optional.toCollection(destination)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected Optional.toCollection to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let toCollectionCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toCollection"
            })
            let chosenToCollection = try XCTUnwrap(
                sema.bindings.callBinding(for: toCollectionCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenToCollection),
                "kk_optional_toCollection"
            )
        }
    }

    func testOptionalGetOrNullSignature() throws {
        let (sema, interner) = try makeSema()

        let optionalFQName = ["java", "util", "Optional"].map { interner.intern($0) }
        let optionalSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: optionalFQName),
            "Expected java.util.Optional to be registered"
        )

        let getOrNullFQName = ["kotlin", "jvm", "optionals", "getOrNull"].map { interner.intern($0) }
        let getOrNullSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: getOrNullFQName),
            "Expected kotlin.jvm.optionals.getOrNull to be registered"
        )
        let getOrNullSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getOrNullSymbol))
        XCTAssertTrue(sema.symbols.symbol(getOrNullSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: getOrNullSymbol), "kk_optional_getOrNull")

        let functionTParamSymbol = try XCTUnwrap(getOrNullSignature.typeParameterSymbols.first)
        let functionTType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.out(functionTType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(getOrNullSignature.receiverType, receiverType)
        XCTAssertEqual(getOrNullSignature.parameterTypes, [])
        XCTAssertEqual(getOrNullSignature.returnType, sema.types.makeNullable(functionTType))
        XCTAssertEqual(getOrNullSignature.typeParameterSymbols, [functionTParamSymbol])
        XCTAssertEqual(getOrNullSignature.classTypeParameterCount, 0)
    }

    func testOptionalGetOrNullResolvesInSource() throws {
        let source = """
        import java.util.Optional
        import kotlin.jvm.optionals.getOrNull

        fun probe(optional: Optional<String>): String? {
            return optional.getOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected Optional.getOrNull to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let getOrNullCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "getOrNull"
            })
            let chosenGetOrNull = try XCTUnwrap(
                sema.bindings.callBinding(for: getOrNullCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenGetOrNull),
                "kk_optional_getOrNull"
            )
        }
    }

    func testOptionalAsSequenceSignature() throws {
        let (sema, interner) = try makeSema()

        let optionalFQName = ["java", "util", "Optional"].map { interner.intern($0) }
        let optionalSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: optionalFQName),
            "Expected java.util.Optional to be registered"
        )

        let asSequenceFQName = ["kotlin", "jvm", "optionals", "asSequence"].map { interner.intern($0) }
        let asSequenceSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: asSequenceFQName),
            "Expected kotlin.jvm.optionals.asSequence to be registered"
        )
        let asSequenceSignature = try XCTUnwrap(sema.symbols.functionSignature(for: asSequenceSymbol))
        XCTAssertTrue(sema.symbols.symbol(asSequenceSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: asSequenceSymbol), "kk_optional_asSequence")

        let functionTParamSymbol = try XCTUnwrap(asSequenceSignature.typeParameterSymbols.first)
        let functionTType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.out(functionTType)],
            nullability: .nonNull
        )))
        let sequenceSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map { interner.intern($0) })
        )
        let sequenceType = sema.types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(functionTType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(asSequenceSignature.receiverType, receiverType)
        XCTAssertEqual(asSequenceSignature.parameterTypes, [])
        XCTAssertEqual(asSequenceSignature.returnType, sequenceType)
        XCTAssertEqual(asSequenceSignature.typeParameterSymbols, [functionTParamSymbol])
        XCTAssertEqual(asSequenceSignature.classTypeParameterCount, 0)
    }

    func testOptionalAsSequenceResolvesInSource() throws {
        let source = """
        import java.util.Optional
        import kotlin.jvm.optionals.asSequence

        fun probe(optional: Optional<String>): Sequence<String> {
            return optional.asSequence()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let asSequenceCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "asSequence"
            })
            let chosenAsSequence = try XCTUnwrap(
                sema.bindings.callBinding(for: asSequenceCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenAsSequence),
                "kk_optional_asSequence"
            )
        }
    }

    func testOptionalToSetSignature() throws {
        let (sema, interner) = try makeSema()

        let optionalFQName = ["java", "util", "Optional"].map { interner.intern($0) }
        let optionalSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: optionalFQName),
            "Expected java.util.Optional to be registered"
        )
        let setSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Set"].map { interner.intern($0) }),
            "Expected kotlin.collections.Set to be registered"
        )

        let toSetFQName = ["kotlin", "jvm", "optionals", "toSet"].map { interner.intern($0) }
        let toSetSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: toSetFQName),
            "Expected kotlin.jvm.optionals.toSet to be registered"
        )
        let toSetSignature = try XCTUnwrap(sema.symbols.functionSignature(for: toSetSymbol))
        XCTAssertTrue(sema.symbols.symbol(toSetSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: toSetSymbol), "kk_optional_toSet")

        let functionTParamSymbol = try XCTUnwrap(toSetSignature.typeParameterSymbols.first)
        let functionTType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: optionalSymbol,
            args: [.out(functionTType)],
            nullability: .nonNull
        )))
        let setType = sema.types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(functionTType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(toSetSignature.receiverType, receiverType)
        XCTAssertEqual(toSetSignature.parameterTypes, [])
        XCTAssertEqual(toSetSignature.returnType, setType)
        XCTAssertEqual(toSetSignature.typeParameterSymbols, [functionTParamSymbol])
        XCTAssertEqual(toSetSignature.classTypeParameterCount, 0)
    }

    func testOptionalToSetResolvesInSource() throws {
        let source = """
        import java.util.Optional
        import kotlin.jvm.optionals.toSet

        fun probe(optional: Optional<String>): Set<String> {
            return optional.toSet()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected Optional.toSet to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let toSetCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toSet"
            })
            let chosenToSet = try XCTUnwrap(
                sema.bindings.callBinding(for: toSetCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenToSet),
                "kk_optional_toSet"
            )
        }
    }
}
