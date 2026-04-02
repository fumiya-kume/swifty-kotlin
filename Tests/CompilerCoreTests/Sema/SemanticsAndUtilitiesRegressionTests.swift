@testable import CompilerCore
import Foundation
import XCTest

final class SemanticsAndUtilitiesRegressionTests: XCTestCase {
    func testAtomicStoreExpressionIsTypedAsUnit() throws {
        let source = """
        import kotlin.concurrent.AtomicInt

        fun main() {
            val ai = AtomicInt(1)
            val x = ai.store(2)
            val y: Unit = x
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Atomic.store() should be typed as Unit: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAtomicArrayStubsAreRegisteredWithSharedClassAndFunctionName() throws {
        let source = """
        import kotlin.concurrent.atomics.AtomicArray
        import kotlin.concurrent.atomics.atomicArrayOfNulls

        fun main(source: Array<Int>) {
            val copied = AtomicArray(source)
            val sized = AtomicArray(2) { it }
            val nulls = atomicArrayOfNulls<Int>(2)
            val size = copied.size
            val first = copied.loadAt(0)
            copied.storeAt(0, 1)
            copied.exchangeAt(0, 2)
            copied.compareAndSetAt(0, 1, 2)
            copied.compareAndExchangeAt(0, 1, 2)
            copied.fetchAndUpdateAt(0) { it + 1 }
            copied.updateAndFetchAt(0) { it + 1 }
            copied.updateAt(0) { it + 1 }
            val text = copied.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "AtomicArray stubs should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let atomicArrayFQName = [
                interner.intern("kotlin"),
                interner.intern("concurrent"),
                interner.intern("atomics"),
                interner.intern("AtomicArray"),
            ]

            let atomicArraySymbols = sema.symbols.lookupAll(fqName: atomicArrayFQName)
            let atomicArrayClassSymbol = try XCTUnwrap(
                atomicArraySymbols.first(where: { sema.symbols.symbol($0)?.kind == .class })
            )
            let atomicArrayFunctionSymbol = try XCTUnwrap(
                atomicArraySymbols.first(where: { sema.symbols.symbol($0)?.kind == .function })
            )
            XCTAssertFalse(atomicArrayClassSymbol == atomicArrayFunctionSymbol)

            let classTypeParameters = sema.types.nominalTypeParameterSymbols(for: atomicArrayClassSymbol)
            XCTAssertEqual(classTypeParameters.count, 1)
            let classTypeParamSymbol = try XCTUnwrap(classTypeParameters.first)
            XCTAssertEqual(sema.symbols.symbol(classTypeParamSymbol)?.name, interner.intern("T"))
            XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: atomicArrayClassSymbol), [.invariant])

            let constructorFQName = atomicArrayFQName + [interner.intern("<init>")]
            let constructorSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: constructorFQName).first(where: { sema.symbols.symbol($0)?.kind == .constructor })
            )
            let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
            XCTAssertEqual(constructorSignature.parameterTypes.count, 1)
            XCTAssertEqual(constructorSignature.classTypeParameterCount, 1)
            XCTAssertEqual(constructorSignature.typeParameterSymbols, [classTypeParamSymbol])
            XCTAssertFalse(sema.symbols.symbol(constructorSymbol)?.flags.contains(.throwingFunction) ?? true)

            switch sema.types.kind(of: constructorSignature.parameterTypes[0]) {
            case let .classType(classType):
                XCTAssertEqual(sema.symbols.symbol(classType.classSymbol)?.name, interner.intern("Array"))
                XCTAssertEqual(classType.args.count, 1)
                switch classType.args[0] {
                case let .invariant(argType):
                    switch sema.types.kind(of: argType) {
                    case let .typeParam(typeParamType):
                        XCTAssertEqual(typeParamType.symbol, classTypeParamSymbol)
                        XCTAssertEqual(typeParamType.nullability, .nonNull)
                    default:
                        XCTFail("Expected AtomicArray(array:) to take Array<T>.")
                    }
                default:
                    XCTFail("Expected AtomicArray(array:) to take invariant Array<T>.")
                }
            default:
                XCTFail("Expected AtomicArray(array:) to take Array<T>.")
            }

            let factorySignature = try XCTUnwrap(sema.symbols.functionSignature(for: atomicArrayFunctionSymbol))
            XCTAssertEqual(factorySignature.parameterTypes.count, 2)
            XCTAssertEqual(factorySignature.typeParameterSymbols.count, 1)
            XCTAssertEqual(factorySignature.classTypeParameterCount, 0)
            XCTAssertTrue(sema.symbols.symbol(atomicArrayFunctionSymbol)?.flags.contains(.throwingFunction) ?? false)
            let factoryTypeParamSymbol = try XCTUnwrap(factorySignature.typeParameterSymbols.first)
            XCTAssertNotEqual(factoryTypeParamSymbol, classTypeParamSymbol)

            switch sema.types.kind(of: factorySignature.returnType) {
            case let .classType(classType):
                XCTAssertEqual(sema.symbols.symbol(classType.classSymbol)?.name, interner.intern("AtomicArray"))
                XCTAssertEqual(classType.args.count, 1)
                switch classType.args[0] {
                case let .invariant(argType):
                    switch sema.types.kind(of: argType) {
                    case let .typeParam(typeParamType):
                        XCTAssertEqual(typeParamType.symbol, factoryTypeParamSymbol)
                        XCTAssertEqual(typeParamType.nullability, .nonNull)
                    default:
                        XCTFail("Expected AtomicArray(size, init) to return AtomicArray<T>.")
                    }
                default:
                    XCTFail("Expected AtomicArray(size, init) to return AtomicArray<T>.")
                }
            default:
                XCTFail("Expected AtomicArray(size, init) to return AtomicArray<T>.")
            }

            switch sema.types.kind(of: factorySignature.parameterTypes[1]) {
            case let .functionType(functionType):
                XCTAssertEqual(functionType.params.count, 1)
                switch sema.types.kind(of: functionType.returnType) {
                case let .typeParam(typeParamType):
                    XCTAssertEqual(typeParamType.symbol, factoryTypeParamSymbol)
                default:
                    XCTFail("Expected AtomicArray(size, init) lambda to return T.")
                }
            default:
                XCTFail("Expected AtomicArray(size, init) lambda parameter to be a function type.")
            }

            let ofNullsFQName = [
                interner.intern("kotlin"),
                interner.intern("concurrent"),
                interner.intern("atomics"),
                interner.intern("atomicArrayOfNulls"),
            ]
            let ofNullsSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: ofNullsFQName).first(where: { sema.symbols.symbol($0)?.kind == .function })
            )
            let ofNullsSignature = try XCTUnwrap(sema.symbols.functionSignature(for: ofNullsSymbol))
            XCTAssertEqual(ofNullsSignature.parameterTypes.count, 1)
            XCTAssertEqual(ofNullsSignature.typeParameterSymbols.count, 1)
            XCTAssertEqual(ofNullsSignature.classTypeParameterCount, 0)
            XCTAssertFalse(sema.symbols.symbol(ofNullsSymbol)?.flags.contains(.throwingFunction) ?? true)
            let ofNullsTypeParamSymbol = try XCTUnwrap(ofNullsSignature.typeParameterSymbols.first)
            XCTAssertNotEqual(ofNullsTypeParamSymbol, classTypeParamSymbol)

            switch sema.types.kind(of: ofNullsSignature.returnType) {
            case let .classType(classType):
                XCTAssertEqual(sema.symbols.symbol(classType.classSymbol)?.name, interner.intern("AtomicArray"))
                XCTAssertEqual(classType.args.count, 1)
                switch classType.args[0] {
                case let .invariant(argType):
                    switch sema.types.kind(of: argType) {
                    case let .typeParam(typeParamType):
                        XCTAssertEqual(typeParamType.symbol, ofNullsTypeParamSymbol)
                        XCTAssertEqual(typeParamType.nullability, .nullable)
                    default:
                        XCTFail("Expected atomicArrayOfNulls<T> to return AtomicArray<T?>.")
                    }
                default:
                    XCTFail("Expected atomicArrayOfNulls<T> to return AtomicArray<T?>.")
                }
            default:
                XCTFail("Expected atomicArrayOfNulls<T> to return AtomicArray<T?>.")
            }

            let sizeFQName = atomicArrayFQName + [interner.intern("size")]
            let sizeSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: sizeFQName).first(where: { sema.symbols.symbol($0)?.kind == .property })
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: sizeSymbol), "kk_atomic_array_size")
            XCTAssertFalse(sema.symbols.symbol(sizeSymbol)?.flags.contains(.throwingFunction) ?? true)

            let throwingMemberNames = [
                "loadAt",
                "storeAt",
                "exchangeAt",
                "compareAndSetAt",
                "compareAndExchangeAt",
                "fetchAndUpdateAt",
                "updateAndFetchAt",
                "updateAt",
            ]
            for memberName in throwingMemberNames {
                let memberFQName = atomicArrayFQName + [interner.intern(memberName)]
                let memberSymbol = try XCTUnwrap(
                    sema.symbols.lookupAll(fqName: memberFQName).first(where: { sema.symbols.symbol($0)?.kind == .function })
                )
                XCTAssertTrue(sema.symbols.symbol(memberSymbol)?.flags.contains(.throwingFunction) ?? false, "\(memberName) should be marked throwing.")
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: memberSymbol))
                XCTAssertEqual(signature.classTypeParameterCount, 1)
                XCTAssertEqual(signature.typeParameterSymbols, [classTypeParamSymbol])
            }

            let toStringSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: atomicArrayFQName + [interner.intern("toString")]).first(where: { sema.symbols.symbol($0)?.kind == .function })
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: toStringSymbol), "kk_atomic_array_toString")
            XCTAssertFalse(sema.symbols.symbol(toStringSymbol)?.flags.contains(.throwingFunction) ?? true)
        }
    }

    func testTypeSystemLUBAndGLB() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))
        let boolNN = types.make(.primitive(.boolean, .nonNull))

        XCTAssertEqual(types.lub([]), types.errorType)
        XCTAssertEqual(types.lub([intNN, intNN]), intNN)
        XCTAssertEqual(types.lub([intNN, intNullable]), types.nullableAnyType)

        XCTAssertEqual(types.glb([]), types.errorType)
        XCTAssertEqual(types.glb([intNN, intNN]), intNN)
        XCTAssertEqual(types.glb([intNN, types.nothingType]), types.nothingType)

        let glbMixed = types.glb([intNN, boolNN])
        XCTAssertEqual(types.kind(of: glbMixed), .intersection([intNN, boolNN]))

        XCTAssertEqual(types.kind(of: TypeID(rawValue: 9999)), .error)
    }

    func testTypeSystemAnyNonNullSubtypeCoversClassFunctionIntersectionAndDefaultCases() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))

        let classNN = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nonNull
        )))
        let classNullable = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nullable
        )))

        let fnNN = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnNullable = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nullable
        )))

        let intersectionAllNonNull = types.make(.intersection([intNN, classNN]))
        let intersectionWithNullable = types.make(.intersection([intNN, intNullable]))

        XCTAssertTrue(types.isSubtype(classNN, types.anyType))
        XCTAssertFalse(types.isSubtype(classNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(fnNN, types.anyType))
        XCTAssertFalse(types.isSubtype(fnNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(intersectionAllNonNull, types.anyType))
        // With corrected intersection subtype rules (P5-97): A & B <: C if ANY part <: C.
        // intersection([Int, Int?]) <: Any is true because Int <: Any.
        XCTAssertTrue(types.isSubtype(intersectionWithNullable, types.anyType))
        XCTAssertFalse(types.isSubtype(types.nullableAnyType, types.anyType))

        let fnWithReceiver = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnWithoutReceiver = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(fnWithReceiver, fnWithoutReceiver))
    }

    func testSemanticsBindingTableAndSymbolTableScopes() {
        let interner = StringInterner()
        let symbols = SymbolTable()

        let pkg = symbols.define(
            kind: .package,
            name: interner.intern("pkg"),
            fqName: [interner.intern("pkg")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let fn = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: [interner.intern("pkg"), interner.intern("run")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .suspendFunction]
        )

        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols.symbol(pkg)?.kind, .package)
        XCTAssertEqual(symbols.lookup(fqName: [interner.intern("pkg")]), pkg)

        let signature = FunctionSignature(parameterTypes: [TypeSystem().anyType], returnType: TypeSystem().unitType)
        symbols.setFunctionSignature(signature, for: fn)
        XCTAssertEqual(symbols.functionSignature(for: fn)?.parameterTypes.count, 1)

        let root = PackageScope(parent: nil, symbols: symbols)
        let fileScope = FileScope(parent: root, symbols: symbols)
        fileScope.insert(fn)
        XCTAssertEqual(fileScope.lookup(interner.intern("run")), [fn])
        XCTAssertTrue(root.lookup(interner.intern("run")).isEmpty)

        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let decl = DeclID(rawValue: 2)
        bindings.bindExprType(expr, type: TypeSystem().anyType)
        bindings.bindIdentifier(expr, symbol: fn)
        bindings.bindCall(expr, binding: CallBinding(chosenCallee: fn, substitutedTypeArguments: [], parameterMapping: [0: 0]))
        bindings.bindCallableTarget(expr, target: .symbol(fn))
        bindings.bindCallableValueCall(
            expr,
            binding: CallableValueCallBinding(
                target: .localValue(fn),
                functionType: TypeSystem().anyType,
                parameterMapping: [0: 0]
            )
        )
        bindings.bindCallableTarget(expr, target: .localValue(fn))
        bindings.bindCaptureSymbols(expr, symbols: [fn, fn])
        bindings.bindDecl(decl, symbol: fn)
        bindings.bindCatchClause(expr, binding: CatchClauseBinding(parameterSymbol: fn, parameterType: TypeSystem().anyType))

        XCTAssertEqual(bindings.identifierSymbol(for: expr), fn)
        XCTAssertEqual(bindings.callBinding(for: expr)?.chosenCallee, fn)
        XCTAssertEqual(bindings.callableTarget(for: expr), .localValue(fn))
        XCTAssertEqual(bindings.callableValueCallBinding(for: expr)?.parameterMapping, [0: 0])
        XCTAssertEqual(bindings.catchClauseBinding(for: expr)?.parameterSymbol, fn)
        XCTAssertEqual(bindings.captureSymbols(for: expr), [fn])
        XCTAssertEqual(bindings.declSymbol(for: decl), fn)
        XCTAssertFalse(bindings.isSuperCallExpr(expr))
    }

    func testImportAliasDeclStoresAliasField() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 10)

        let noAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: nil)
        XCTAssertNil(noAlias.alias)

        let withAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: interner.intern("X"))
        XCTAssertEqual(withAlias.alias, interner.intern("X"))
    }

    func testConditionBranchStructCreation() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 100)
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let trueState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true),
        ])
        let falseState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [stringType], nullability: .nonNull, isStable: true),
        ])
        let branch = ConditionBranch(trueState: trueState, falseState: falseState)

        XCTAssertEqual(branch.trueState.variables[sym]?.possibleTypes, [intType])
        XCTAssertEqual(branch.falseState.variables[sym]?.possibleTypes, [stringType])

        let merged = analyzer.merge(branch.trueState, branch.falseState)
        XCTAssertEqual(merged.variables[sym]?.possibleTypes.count, 2)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(intType) == true)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(stringType) == true)
    }
}

final class CommandRunnerErrorPathTests: XCTestCase {
    func testRunReturnsStdoutOnSuccess() throws {
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-c", "printf 'ok'"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ok")
    }

    func testRunThrowsNonZeroExitWithCapturedStderr() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["sh", "-c", "printf 'err' >&2; exit 7"]
            )
        ) { error in
            guard case let CommandRunnerError.nonZeroExit(result) = error else {
                XCTFail("Expected nonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(result.exitCode, 7)
            XCTAssertEqual(result.stderr, "err")
        }
    }

    func testRunThrowsLaunchFailedForMissingExecutable() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/definitely/missing/executable",
                arguments: []
            )
        ) { error in
            guard case let CommandRunnerError.launchFailed(message) = error else {
                XCTFail("Expected launchFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Failed to launch"))
        }
    }
}
