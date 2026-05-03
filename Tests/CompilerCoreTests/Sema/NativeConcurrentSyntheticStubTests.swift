@testable import CompilerCore
import Foundation
import XCTest

// MARK: - kotlin.native.concurrent sema / diagnostics coverage (STDLIB-NATIVE-CONCURRENT-002)

final class NativeConcurrentSyntheticStubTests: XCTestCase {

    // MARK: Helpers

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    private func symbol(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: path.map { interner.intern($0) }),
            "Expected \(path.joined(separator: ".")) to be registered",
            file: file,
            line: line
        )
    }

    private func classType(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner,
        args: [TypeArg] = [],
        nullability: Nullability = .nonNull,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let classSymbol = try symbol(path, sema: sema, interner: interner, file: file, line: line)
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: args,
            nullability: nullability
        )))
    }

    private func memberFunction(
        ownerPath: [String],
        named name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        let ownerType = try classType(ownerPath, sema: sema, interner: interner, file: file, line: line)
        let functionFQName = (ownerPath + [name]).map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: functionFQName)
        return try XCTUnwrap(candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }, "Expected \(ownerPath.joined(separator: ".")).\(name)", file: file, line: line)
    }

    private func assertMutableProperty(
        ownerPath: [String],
        named name: String,
        type expectedType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let property = try symbol(ownerPath + [name], sema: sema, interner: interner, file: file, line: line)
        XCTAssertEqual(sema.symbols.symbol(property)?.kind, .property, file: file, line: line)
        XCTAssertEqual(sema.symbols.propertyType(for: property), expectedType, file: file, line: line)
        XCTAssertTrue(
            sema.symbols.symbol(property)?.flags.contains(.mutable) == true,
            "\(ownerPath.joined(separator: ".")).\(name) should be mutable",
            file: file,
            line: line
        )
    }

    private func nativeContinuationInvokerType(
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let nullableCOpaquePointerType = sema.types.makeNullable(try classType(
            ["kotlinx", "cinterop", "COpaquePointer"],
            sema: sema,
            interner: interner,
            file: file,
            line: line
        ))
        let invokerCallbackType = sema.types.make(.functionType(FunctionType(
            params: [nullableCOpaquePointerType],
            returnType: sema.types.unitType
        )))
        let cFunctionType = try classType(
            ["kotlinx", "cinterop", "CFunction"],
            sema: sema,
            interner: interner,
            args: [.invariant(invokerCallbackType)],
            file: file,
            line: line
        )
        return try classType(
            ["kotlinx", "cinterop", "CPointer"],
            sema: sema,
            interner: interner,
            args: [.invariant(cFunctionType)],
            file: file,
            line: line
        )
    }

    // MARK: - TransferMode enum

    func testTransferModeEnumIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "TransferMode"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.TransferMode to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .enumClass)
    }

    func testTransferModeSafeEntryHasCorrectType() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "native", "concurrent", "TransferMode"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let safeFQName = enumFQName + [interner.intern("SAFE")]
        let safeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: safeFQName),
            "Expected TransferMode.SAFE entry"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: safeSymbol), enumType)
    }

    func testTransferModeUnsafeEntryHasCorrectType() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "native", "concurrent", "TransferMode"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let unsafeFQName = enumFQName + [interner.intern("UNSAFE")]
        let unsafeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: unsafeFQName))
        XCTAssertEqual(sema.symbols.propertyType(for: unsafeSymbol), enumType)
    }

    func testTransferModeResolvesInSource() throws {
        let source = """
        import kotlin.native.concurrent.TransferMode

        fun probe(): TransferMode = TransferMode.SAFE
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected TransferMode.SAFE to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - FutureState enum

    func testFutureStateEnumIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "FutureState"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.FutureState to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .enumClass)
    }

    func testFutureStateEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let baseFQName = ["kotlin", "native", "concurrent", "FutureState"].map { interner.intern($0) }
        for entry in ["SCHEDULED", "COMPUTED", "THROWN", "CANCELLED"] {
            let entryFQName = baseFQName + [interner.intern(entry)]
            XCTAssertNotNil(
                sema.symbols.lookup(fqName: entryFQName),
                "Expected FutureState.\(entry) to be registered"
            )
        }
    }

    // MARK: - Continuation0 / Continuation1 / Continuation2 classes

    func testContinuationTypesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        for (name, arity) in [("Continuation0", 0), ("Continuation1", 1), ("Continuation2", 2)] {
            let continuation = try symbol(
                ["kotlin", "native", "concurrent", name],
                sema: sema,
                interner: interner
            )
            let functionSupertype = try symbol(
                ["kotlin", "Function", "Function\(arity)"],
                sema: sema,
                interner: interner
            )

            XCTAssertEqual(sema.symbols.symbol(continuation)?.kind, .class)
            XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: continuation).count, arity)
            XCTAssertTrue(sema.symbols.directSupertypes(for: continuation).contains(functionSupertype))
            XCTAssertTrue(
                sema.symbols.annotations(for: continuation).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "\(name) must carry Deprecated metadata"
            )
        }
    }

    func testContinuationConstructorsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let invokerType = try nativeContinuationInvokerType(sema: sema, interner: interner)

        for (name, arity) in [("Continuation0", 0), ("Continuation1", 1), ("Continuation2", 2)] {
            let continuationFQName = ["kotlin", "native", "concurrent", name].map { interner.intern($0) }
            let continuation = try XCTUnwrap(sema.symbols.lookup(fqName: continuationFQName))
            let typeParameters = sema.types.nominalTypeParameterSymbols(for: continuation)
            let typeParameterTypes = typeParameters.map {
                sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))
            }
            let continuationType = sema.types.make(.classType(ClassType(
                classSymbol: continuation,
                args: typeParameterTypes.map { .invariant($0) },
                nullability: .nonNull
            )))
            let blockType = sema.types.make(.functionType(FunctionType(
                params: typeParameterTypes,
                returnType: sema.types.unitType
            )))

            let constructors = sema.symbols.lookupAll(fqName: continuationFQName + [interner.intern("<init>")])
            let constructor = try XCTUnwrap(constructors.first { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.parameterTypes == [blockType, invokerType, sema.types.booleanType]
                    && signature.returnType == continuationType
            }, "Expected \(name) constructor")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

            XCTAssertEqual(sema.symbols.symbol(constructor)?.kind, .constructor)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false, true])
            XCTAssertEqual(signature.typeParameterSymbols, typeParameters)
            XCTAssertEqual(signature.classTypeParameterCount, arity)
        }
    }

    func testContinuationMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()

        for (name, arity) in [("Continuation0", 0), ("Continuation1", 1), ("Continuation2", 2)] {
            let continuationFQName = ["kotlin", "native", "concurrent", name].map { interner.intern($0) }
            let continuation = try XCTUnwrap(sema.symbols.lookup(fqName: continuationFQName))
            let typeParameters = sema.types.nominalTypeParameterSymbols(for: continuation)
            let typeParameterTypes = typeParameters.map {
                sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))
            }
            let continuationType = sema.types.make(.classType(ClassType(
                classSymbol: continuation,
                args: typeParameterTypes.map { .invariant($0) },
                nullability: .nonNull
            )))

            let dispose = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: continuationFQName + [interner.intern("dispose")]).first,
                "Expected \(name).dispose"
            )
            let disposeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: dispose))
            XCTAssertEqual(disposeSignature.receiverType, continuationType)
            XCTAssertEqual(disposeSignature.parameterTypes, [])
            XCTAssertEqual(disposeSignature.returnType, sema.types.unitType)
            XCTAssertEqual(disposeSignature.classTypeParameterCount, arity)

            let invoke = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: continuationFQName + [interner.intern("invoke")]).first,
                "Expected \(name).invoke"
            )
            let invokeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: invoke))
            XCTAssertEqual(invokeSignature.receiverType, continuationType)
            XCTAssertEqual(invokeSignature.parameterTypes, typeParameterTypes)
            XCTAssertEqual(invokeSignature.returnType, sema.types.unitType)
            XCTAssertEqual(invokeSignature.classTypeParameterCount, arity)
            XCTAssertTrue(sema.symbols.symbol(invoke)?.flags.contains(.operatorFunction) == true)
            XCTAssertTrue(sema.symbols.symbol(invoke)?.flags.contains(.overrideMember) == true)
        }
    }

    func testContinuationTypesResolveInSource() {
        let source = """
        import kotlin.native.concurrent.Continuation0
        import kotlin.native.concurrent.Continuation1
        import kotlin.native.concurrent.Continuation2

        fun accept0(c: Continuation0) {
            c.dispose()
            c.invoke()
            c()
        }

        fun accept1(c: Continuation1<Int>) {
            c.dispose()
            c.invoke(1)
            c(1)
        }

        fun accept2(c: Continuation2<Int, String>) {
            c.dispose()
            c.invoke(1, "x")
            c(1, "x")
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Continuation types to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testCallContinuationFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let receiverType = try classType(
            ["kotlinx", "cinterop", "COpaquePointer"],
            sema: sema,
            interner: interner
        )

        for arity in 0...2 {
            let functionFQName = ["kotlin", "native", "concurrent", "callContinuation\(arity)"]
                .map { interner.intern($0) }
            let function = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.unitType
                    && signature.typeParameterSymbols.count == arity
            }, "Expected callContinuation\(arity)")
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

            XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
            XCTAssertEqual(signature.classTypeParameterCount, 0)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertTrue(
                sema.symbols.annotations(for: function).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "callContinuation\(arity) must carry Deprecated metadata"
            )
        }
    }

    func testCallContinuationFunctionsResolveInSource() {
        let source = """
        import kotlinx.cinterop.COpaquePointer
        import kotlin.native.concurrent.callContinuation0
        import kotlin.native.concurrent.callContinuation1
        import kotlin.native.concurrent.callContinuation2

        fun probe(pointer: COpaquePointer) {
            pointer.callContinuation0()
            pointer.callContinuation1<Int>()
            pointer.callContinuation2<Int, String>()
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected callContinuation functions to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testWaitForMultipleFuturesFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "native", "concurrent", "waitForMultipleFutures"]
            .map { interner.intern($0) }
        let functions = sema.symbols.lookupAll(fqName: functionFQName)
        let topLevel = try XCTUnwrap(functions.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 2
                && signature.typeParameterSymbols.count == 1
        }, "Expected top-level waitForMultipleFutures")
        let topLevelSignature = try XCTUnwrap(sema.symbols.functionSignature(for: topLevel))
        let topLevelTypeParameter = try XCTUnwrap(topLevelSignature.typeParameterSymbols.first)
        let topLevelT = sema.types.make(.typeParam(TypeParamType(
            symbol: topLevelTypeParameter,
            nullability: .nonNull
        )))
        let topLevelFutureType = try classType(
            ["kotlin", "native", "concurrent", "Future"],
            sema: sema,
            interner: interner,
            args: [.invariant(topLevelT)]
        )
        let topLevelCollectionType = try classType(
            ["kotlin", "collections", "Collection"],
            sema: sema,
            interner: interner,
            args: [.out(topLevelFutureType)]
        )
        let topLevelSetType = try classType(
            ["kotlin", "collections", "Set"],
            sema: sema,
            interner: interner,
            args: [.out(topLevelFutureType)]
        )

        XCTAssertEqual(topLevelSignature.parameterTypes, [topLevelCollectionType, sema.types.intType])
        XCTAssertEqual(topLevelSignature.returnType, topLevelSetType)
        XCTAssertTrue(sema.symbols.annotations(for: topLevel).contains {
            $0.annotationFQName == "kotlin.native.concurrent.ObsoleteWorkersApi"
        })

        let extensionFunction = try XCTUnwrap(functions.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType != nil
                && signature.parameterTypes == [sema.types.intType]
                && signature.typeParameterSymbols.count == 1
        }, "Expected extension waitForMultipleFutures")
        let extensionSignature = try XCTUnwrap(sema.symbols.functionSignature(for: extensionFunction))
        XCTAssertEqual(extensionSignature.returnType, topLevelSetType)
        XCTAssertTrue(sema.symbols.annotations(for: extensionFunction).contains {
            $0.annotationFQName == "kotlin.native.concurrent.ObsoleteWorkersApi"
        })
        XCTAssertTrue(sema.symbols.annotations(for: extensionFunction).contains {
            $0.annotationFQName == "kotlin.Deprecated"
        })
    }

    func testWaitForMultipleFuturesTopLevelResolvesInSource() {
        let source = """
        import kotlin.native.concurrent.Future
        import kotlin.native.concurrent.waitForMultipleFutures

        fun probe(futures: Collection<Future<Int>>): Set<Future<Int>> =
            waitForMultipleFutures(futures, 1)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected waitForMultipleFutures to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testWaitWorkerTerminationFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "native", "concurrent", "waitWorkerTermination"]
            .map { interner.intern($0) }
        let workerType = try classType(
            ["kotlin", "native", "concurrent", "Worker"],
            sema: sema,
            interner: interner
        )
        let function = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes == [workerType]
                && signature.returnType == sema.types.unitType
        }, "Expected waitWorkerTermination")
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.native.concurrent.ObsoleteWorkersApi"
        })
    }

    func testWaitWorkerTerminationResolvesInSource() {
        let source = """
        import kotlin.native.concurrent.Worker
        import kotlin.native.concurrent.waitWorkerTermination

        fun probe(worker: Worker) {
            waitWorkerTermination(worker)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected waitWorkerTermination to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testWithWorkerFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "native", "concurrent", "withWorker"]
            .map { interner.intern($0) }
        let workerType = try classType(
            ["kotlin", "native", "concurrent", "Worker"],
            sema: sema,
            interner: interner
        )
        let function = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 3
                && signature.typeParameterSymbols.count == 1
        }, "Expected withWorker")
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let returnType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let blockType = sema.types.make(.functionType(FunctionType(
            receiver: workerType,
            params: [],
            returnType: returnType
        )))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertEqual(signature.parameterTypes, [
            sema.types.makeNullable(sema.types.stringType),
            sema.types.booleanType,
            blockType,
        ])
        XCTAssertEqual(signature.returnType, returnType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, true, false])
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.native.concurrent.ObsoleteWorkersApi"
        })
    }

    func testWithWorkerResolvesInSource() {
        let source = """
        import kotlin.native.concurrent.withWorker

        fun probe(): Int =
            withWorker<Int>("worker", true) { 1 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected withWorker to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - DetachedObjectGraph<T> class

    func testDetachedObjectGraphClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let graph = try symbol(
            ["kotlin", "native", "concurrent", "DetachedObjectGraph"],
            sema: sema,
            interner: interner
        )

        XCTAssertEqual(sema.symbols.symbol(graph)?.kind, .class)
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: graph).count, 1)
    }

    func testDetachedObjectGraphProducerConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let graphFQName = ["kotlin", "native", "concurrent", "DetachedObjectGraph"]
            .map { interner.intern($0) }
        let graph = try XCTUnwrap(sema.symbols.lookup(fqName: graphFQName))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: graph).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let graphType = sema.types.make(.classType(ClassType(
            classSymbol: graph,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let transferModeType = try classType(
            ["kotlin", "native", "concurrent", "TransferMode"],
            sema: sema,
            interner: interner
        )
        let producerType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: typeParameterType
        )))

        let constructors = sema.symbols.lookupAll(fqName: graphFQName + [interner.intern("<init>")])
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [transferModeType, producerType]
                && signature.returnType == graphType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(sema.symbols.symbol(constructor)?.kind, .constructor)
        XCTAssertNil(signature.receiverType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, false])
        XCTAssertEqual(signature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
    }

    func testDetachedObjectGraphPointerConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let graphFQName = ["kotlin", "native", "concurrent", "DetachedObjectGraph"]
            .map { interner.intern($0) }
        let graph = try XCTUnwrap(sema.symbols.lookup(fqName: graphFQName))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: graph).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let graphType = sema.types.make(.classType(ClassType(
            classSymbol: graph,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nullableCOpaquePointerType = sema.types.makeNullable(try classType(
            ["kotlinx", "cinterop", "COpaquePointer"],
            sema: sema,
            interner: interner
        ))

        let constructors = sema.symbols.lookupAll(fqName: graphFQName + [interner.intern("<init>")])
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [nullableCOpaquePointerType]
                && signature.returnType == graphType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(sema.symbols.symbol(constructor)?.kind, .constructor)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
    }

    func testDetachedObjectGraphAsCPointerIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let graphFQName = ["kotlin", "native", "concurrent", "DetachedObjectGraph"]
            .map { interner.intern($0) }
        let graph = try XCTUnwrap(sema.symbols.lookup(fqName: graphFQName))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: graph).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let graphType = sema.types.make(.classType(ClassType(
            classSymbol: graph,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nullableCOpaquePointerType = sema.types.makeNullable(try classType(
            ["kotlinx", "cinterop", "COpaquePointer"],
            sema: sema,
            interner: interner
        ))

        let methodFQName = graphFQName + [interner.intern("asCPointer")]
        let method = try XCTUnwrap(sema.symbols.lookupAll(fqName: methodFQName).first)
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: method))

        XCTAssertEqual(signature.receiverType, graphType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, nullableCOpaquePointerType)
        XCTAssertEqual(signature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertNil(sema.symbols.externalLinkName(for: method))
    }

    func testDetachedObjectGraphAttachExtensionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let graph = try symbol(
            ["kotlin", "native", "concurrent", "DetachedObjectGraph"],
            sema: sema,
            interner: interner
        )
        let attachFQName = ["kotlin", "native", "concurrent", "attach"].map { interner.intern($0) }
        let attach = try XCTUnwrap(sema.symbols.lookupAll(fqName: attachFQName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            let receiverType = sema.types.make(.classType(ClassType(
                classSymbol: graph,
                args: [.invariant(typeParameterType)],
                nullability: .nonNull
            )))
            return signature.receiverType == receiverType
                && signature.returnType == typeParameterType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: attach))

        XCTAssertEqual(sema.symbols.symbol(attach)?.kind, .function)
        XCTAssertEqual(signature.classTypeParameterCount, 0)
        XCTAssertNil(sema.symbols.externalLinkName(for: attach))
    }

    // MARK: - FreezingException class

    func testFreezingExceptionClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let freezingException = try symbol(
            ["kotlin", "native", "concurrent", "FreezingException"],
            sema: sema,
            interner: interner
        )
        let runtimeException = try symbol(["kotlin", "RuntimeException"], sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(freezingException)?.kind, .class)
        XCTAssertTrue(sema.symbols.directSupertypes(for: freezingException).contains(runtimeException))
        XCTAssertTrue(
            sema.symbols.annotations(for: freezingException).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            },
            "FreezingException must carry ExperimentalNativeApi metadata"
        )
    }

    func testFreezingExceptionConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let exceptionFQName = ["kotlin", "native", "concurrent", "FreezingException"]
            .map { interner.intern($0) }
        let exception = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exception,
            args: [],
            nullability: .nonNull
        )))

        let constructors = sema.symbols.lookupAll(fqName: exceptionFQName + [interner.intern("<init>")])
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.anyType, sema.types.anyType]
                && signature.returnType == exceptionType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(sema.symbols.symbol(constructor)?.kind, .constructor)
        XCTAssertNil(signature.receiverType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
        XCTAssertNil(sema.symbols.externalLinkName(for: constructor))
    }

    func testFreezingExceptionResolvesInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.concurrent.FreezingException

        fun probe(toFreeze: Any, blocker: Any): RuntimeException =
            FreezingException(toFreeze, blocker)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FreezingException constructor to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - InvalidMutabilityException class

    func testInvalidMutabilityExceptionClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let invalidMutabilityException = try symbol(
            ["kotlin", "native", "concurrent", "InvalidMutabilityException"],
            sema: sema,
            interner: interner
        )
        let runtimeException = try symbol(["kotlin", "RuntimeException"], sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(invalidMutabilityException)?.kind, .class)
        XCTAssertTrue(sema.symbols.directSupertypes(for: invalidMutabilityException).contains(runtimeException))
        XCTAssertTrue(
            sema.symbols.annotations(for: invalidMutabilityException).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            },
            "InvalidMutabilityException must carry ExperimentalNativeApi metadata"
        )
    }

    func testInvalidMutabilityExceptionConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let exceptionFQName = ["kotlin", "native", "concurrent", "InvalidMutabilityException"]
            .map { interner.intern($0) }
        let exception = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exception,
            args: [],
            nullability: .nonNull
        )))

        let constructors = sema.symbols.lookupAll(fqName: exceptionFQName + [interner.intern("<init>")])
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == exceptionType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(sema.symbols.symbol(constructor)?.kind, .constructor)
        XCTAssertNil(signature.receiverType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertNil(sema.symbols.externalLinkName(for: constructor))
    }

    func testInvalidMutabilityExceptionResolvesInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.concurrent.InvalidMutabilityException

        fun probe(message: String): RuntimeException =
            InvalidMutabilityException(message)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected InvalidMutabilityException constructor to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - Worker class

    func testWorkerClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.Worker to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)
    }

    func testWorkerRequestTerminationIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let workerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: workerFQName))

        let methodFQName = workerFQName + [interner.intern("requestTermination")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        XCTAssertFalse(methods.isEmpty, "Expected Worker.requestTermination to be registered")

        let method = try XCTUnwrap(methods.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: method))
        XCTAssertEqual(sig.parameterTypes, [sema.types.booleanType])
        XCTAssertEqual(sig.returnType, sema.types.unitType)

        let workerType = try XCTUnwrap(sema.symbols.propertyType(for: workerSymbol))
        XCTAssertEqual(sig.receiverType, workerType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: method), "kk_worker_request_termination")
    }

    func testWorkerIsTerminatedPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let propFQName = workerFQName + [interner.intern("isTerminated")]
        let propSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: propFQName),
            "Expected Worker.isTerminated property"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: propSymbol), sema.types.booleanType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: propSymbol), "kk_worker_is_terminated")
    }

    func testWorkerNamePropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let propFQName = workerFQName + [interner.intern("name")]
        let propSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: propFQName),
            "Expected Worker.name property"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: propSymbol), sema.types.stringType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: propSymbol), "kk_worker_name")
    }

    func testWorkerCompanionStartIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let companionFQName = ["kotlin", "native", "concurrent", "Worker", "Companion"]
            .map { interner.intern($0) }
        let startFQName = companionFQName + [interner.intern("start")]
        let methods = sema.symbols.lookupAll(fqName: startFQName)
        XCTAssertFalse(methods.isEmpty, "Expected Worker.Companion.start to be registered")

        let method = try XCTUnwrap(methods.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: method))
        XCTAssertEqual(sig.parameterTypes, [sema.types.makeNullable(sema.types.stringType)])
        XCTAssertEqual(sig.valueParameterHasDefaultValues, [true])
        XCTAssertEqual(sema.symbols.externalLinkName(for: method), "kk_worker_new")
    }

    // MARK: - WorkerBoundReference<T> class

    func testWorkerBoundReferenceClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reference = try symbol(
            ["kotlin", "native", "concurrent", "WorkerBoundReference"],
            sema: sema,
            interner: interner
        )
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: reference)

        XCTAssertEqual(sema.symbols.symbol(reference)?.kind, .class)
        XCTAssertEqual(typeParameters.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: reference), [.out])
        XCTAssertEqual(
            sema.symbols.typeParameterUpperBounds(for: try XCTUnwrap(typeParameters.first)),
            [sema.types.anyType]
        )
    }

    func testWorkerBoundReferenceConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let referenceFQName = ["kotlin", "native", "concurrent", "WorkerBoundReference"]
            .map { interner.intern($0) }
        let reference = try XCTUnwrap(sema.symbols.lookup(fqName: referenceFQName))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: reference).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let referenceType = sema.types.make(.classType(ClassType(
            classSymbol: reference,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))

        let constructors = sema.symbols.lookupAll(fqName: referenceFQName + [interner.intern("<init>")])
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [typeParameterType]
                && signature.returnType == referenceType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(sema.symbols.symbol(constructor)?.kind, .constructor)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertNil(sema.symbols.externalLinkName(for: constructor))
    }

    func testWorkerBoundReferencePropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let referenceFQName = ["kotlin", "native", "concurrent", "WorkerBoundReference"]
            .map { interner.intern($0) }
        let reference = try XCTUnwrap(sema.symbols.lookup(fqName: referenceFQName))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: reference).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let nullableTypeParameterType = sema.types.makeNullable(typeParameterType)
        let workerType = try classType(
            ["kotlin", "native", "concurrent", "Worker"],
            sema: sema,
            interner: interner
        )

        let value = try XCTUnwrap(sema.symbols.lookup(fqName: referenceFQName + [interner.intern("value")]))
        let valueOrNull = try XCTUnwrap(
            sema.symbols.lookup(fqName: referenceFQName + [interner.intern("valueOrNull")])
        )
        let worker = try XCTUnwrap(sema.symbols.lookup(fqName: referenceFQName + [interner.intern("worker")]))

        XCTAssertEqual(sema.symbols.propertyType(for: value), typeParameterType)
        XCTAssertEqual(sema.symbols.propertyType(for: valueOrNull), nullableTypeParameterType)
        XCTAssertEqual(sema.symbols.propertyType(for: worker), workerType)
        XCTAssertNil(sema.symbols.externalLinkName(for: value))
        XCTAssertNil(sema.symbols.externalLinkName(for: valueOrNull))
        XCTAssertNil(sema.symbols.externalLinkName(for: worker))
    }

    // MARK: - atomicLazy

    func testAtomicLazyFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let atomicLazyFQName = ["kotlin", "native", "concurrent", "atomicLazy"].map { interner.intern($0) }
        let atomicLazy = try XCTUnwrap(sema.symbols.lookupAll(fqName: atomicLazyFQName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            let initializerType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: typeParameterType
            )))
            guard let lazyType = try? classType(
                ["kotlin", "Lazy"],
                sema: sema,
                interner: interner,
                args: [.invariant(typeParameterType)]
            ) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes == [initializerType]
                && signature.returnType == lazyType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: atomicLazy))
        let initializerSymbol = try XCTUnwrap(signature.valueParameterSymbols.first)

        XCTAssertEqual(sema.symbols.symbol(atomicLazy)?.kind, .function)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.classTypeParameterCount, 0)
        XCTAssertEqual(sema.symbols.propertyType(for: initializerSymbol), signature.parameterTypes.first)
        XCTAssertNil(sema.symbols.externalLinkName(for: atomicLazy))
    }

    // MARK: - ensureNeverFrozen

    func testEnsureNeverFrozenFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "native", "concurrent", "ensureNeverFrozen"].map { interner.intern($0) }
        let function = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == sema.types.anyType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.unitType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertTrue(sema.symbols.symbol(function)?.flags.contains(.throwingFunction) == true)
        XCTAssertTrue(signature.canThrow)
        XCTAssertEqual(signature.valueParameterSymbols, [])
        XCTAssertNil(sema.symbols.externalLinkName(for: function))
    }

    func testEnsureNeverFrozenResolvesInSource() {
        let source = """
        import kotlin.native.concurrent.ensureNeverFrozen

        fun probe(value: Any) {
            value.ensureNeverFrozen()
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ensureNeverFrozen to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - freeze / isFrozen

    func testFreezeFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "native", "concurrent", "freeze"].map { interner.intern($0) }
        let function = try XCTUnwrap(sema.symbols.lookupAll(fqName: functionFQName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            return signature.receiverType == typeParameterType
                && signature.returnType == typeParameterType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertEqual(signature.valueParameterSymbols, [])
        XCTAssertEqual(signature.classTypeParameterCount, 0)
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_freeze_object")
        XCTAssertTrue(
            sema.symbols.annotations(for: function).contains {
                $0.annotationFQName == "kotlin.Deprecated"
                    && $0.arguments.contains("level = DeprecationLevel.ERROR")
                    && $0.arguments.contains("replaceWith = ReplaceWith(\"this\")")
            },
            "freeze must carry Deprecated(ERROR) metadata with a drop-in replacement"
        )
    }

    func testIsFrozenPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let propertyFQName = ["kotlin", "native", "concurrent", "isFrozen"].map { interner.intern($0) }
        let property = try XCTUnwrap(sema.symbols.lookupAll(fqName: propertyFQName).first { candidate in
            sema.symbols.symbol(candidate)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: candidate) == sema.types.nullableAnyType
        })
        let getter = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: property))

        XCTAssertEqual(sema.symbols.propertyType(for: property), sema.types.booleanType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: property), "kk_is_frozen")
        XCTAssertEqual(sema.symbols.externalLinkName(for: getter), "kk_is_frozen")
        XCTAssertEqual(sema.symbols.functionSignature(for: getter)?.receiverType, sema.types.nullableAnyType)
        XCTAssertEqual(sema.symbols.functionSignature(for: getter)?.returnType, sema.types.booleanType)
        XCTAssertTrue(
            sema.symbols.annotations(for: property).contains {
                $0.annotationFQName == "kotlin.Deprecated"
                    && $0.arguments.contains("level = DeprecationLevel.ERROR")
                    && $0.arguments.contains("replaceWith = ReplaceWith(\"false\")")
            },
            "isFrozen must carry Deprecated(ERROR) metadata with false replacement"
        )
    }

    func testFreezeAndIsFrozenResolveInSourceWhenDeprecationErrorIsSuppressed() {
        let source = """
        import kotlin.native.concurrent.freeze
        import kotlin.native.concurrent.isFrozen

        @Suppress("DEPRECATION_ERROR")
        fun probe(value: Any): Boolean {
            val frozen = value.freeze()
            return frozen.isFrozen
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected freeze/isFrozen to resolve with deprecation error suppressed, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - Future<T> class

    func testFutureClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.Future to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)

        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)
        XCTAssertEqual(typeParams.count, 1)
    }

    func testFutureResultPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let propFQName = futureFQName + [interner.intern("result")]
        let propSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: propFQName),
            "Expected Future.result property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propSymbol), "kk_future_result")
    }

    func testFutureConsumeMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let methodFQName = futureFQName + [interner.intern("consume")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        XCTAssertFalse(methods.isEmpty, "Expected Future.consume to be registered")

        let method = try XCTUnwrap(methods.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: method))
        XCTAssertEqual(sig.parameterTypes, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: method), "kk_future_consume")
    }

    func testFutureGetStateMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let methodFQName = futureFQName + [interner.intern("getState")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        XCTAssertFalse(methods.isEmpty, "Expected Future.getState to be registered")

        let method = try XCTUnwrap(methods.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: method))
        XCTAssertEqual(sig.parameterTypes, [])

        let futureStateFQName = ["kotlin", "native", "concurrent", "FutureState"].map { interner.intern($0) }
        let futureStateSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: futureStateFQName))
        let futureStateType = sema.types.make(.classType(ClassType(
            classSymbol: futureStateSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sig.returnType, futureStateType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: method), "kk_future_getState")
    }

    // MARK: - AtomicInt / AtomicLong / AtomicNativePtr (legacy kotlin.native.concurrent)

    func testLegacyAtomicScalarClassesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        for name in ["AtomicInt", "AtomicLong", "AtomicNativePtr"] {
            let atomic = try symbol(
                ["kotlin", "native", "concurrent", name],
                sema: sema,
                interner: interner
            )
            XCTAssertEqual(sema.symbols.symbol(atomic)?.kind, .class)
            XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: atomic), [])
            XCTAssertTrue(
                sema.symbols.annotations(for: atomic).contains {
                    $0.annotationFQName == "kotlin.Deprecated"
                        && $0.arguments.contains("level = DeprecationLevel.ERROR")
                },
                "\(name) must carry Deprecated(ERROR) metadata"
            )
        }
    }

    func testLegacyAtomicIntSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let ownerPath = ["kotlin", "native", "concurrent", "AtomicInt"]
        let ownerType = try classType(ownerPath, sema: sema, interner: interner)
        let valueType = sema.types.intType

        let constructors = sema.symbols.lookupAll(fqName: (ownerPath + ["<init>"]).map { interner.intern($0) })
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [valueType] && signature.returnType == ownerType
        }, "Expected AtomicInt(value: Int)")
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])

        try assertMutableProperty(
            ownerPath: ownerPath,
            named: "value",
            type: valueType,
            sema: sema,
            interner: interner
        )

        let numericMembers: [(String, [TypeID], TypeID)] = [
            ("compareAndSet", [valueType, valueType], sema.types.booleanType),
            ("compareAndSwap", [valueType, valueType], valueType),
            ("getAndSet", [valueType], valueType),
            ("addAndGet", [valueType], valueType),
            ("getAndAdd", [valueType], valueType),
            ("getAndIncrement", [], valueType),
            ("getAndDecrement", [], valueType),
            ("incrementAndGet", [], valueType),
            ("decrementAndGet", [], valueType),
            ("increment", [], sema.types.unitType),
            ("decrement", [], sema.types.unitType),
            ("toString", [], sema.types.stringType),
        ]
        for (name, parameters, returnType) in numericMembers {
            _ = try memberFunction(
                ownerPath: ownerPath,
                named: name,
                parameterTypes: parameters,
                returnType: returnType,
                sema: sema,
                interner: interner
            )
        }
    }

    func testLegacyAtomicLongSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let ownerPath = ["kotlin", "native", "concurrent", "AtomicLong"]
        let ownerType = try classType(ownerPath, sema: sema, interner: interner)
        let valueType = sema.types.longType

        let constructors = sema.symbols.lookupAll(fqName: (ownerPath + ["<init>"]).map { interner.intern($0) })
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [valueType] && signature.returnType == ownerType
        }, "Expected AtomicLong(value: Long = 0)")
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [true])

        try assertMutableProperty(
            ownerPath: ownerPath,
            named: "value",
            type: valueType,
            sema: sema,
            interner: interner
        )

        let numericMembers: [(String, [TypeID], TypeID)] = [
            ("compareAndSet", [valueType, valueType], sema.types.booleanType),
            ("compareAndSwap", [valueType, valueType], valueType),
            ("getAndSet", [valueType], valueType),
            ("addAndGet", [sema.types.intType], valueType),
            ("addAndGet", [valueType], valueType),
            ("getAndAdd", [valueType], valueType),
            ("getAndIncrement", [], valueType),
            ("getAndDecrement", [], valueType),
            ("incrementAndGet", [], valueType),
            ("decrementAndGet", [], valueType),
            ("increment", [], sema.types.unitType),
            ("decrement", [], sema.types.unitType),
            ("toString", [], sema.types.stringType),
        ]
        for (name, parameters, returnType) in numericMembers {
            _ = try memberFunction(
                ownerPath: ownerPath,
                named: name,
                parameterTypes: parameters,
                returnType: returnType,
                sema: sema,
                interner: interner
            )
        }
    }

    func testLegacyAtomicNativePtrSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let ownerPath = ["kotlin", "native", "concurrent", "AtomicNativePtr"]
        let ownerType = try classType(ownerPath, sema: sema, interner: interner)
        let valueType = try classType(["kotlinx", "cinterop", "NativePtr"], sema: sema, interner: interner)

        let constructors = sema.symbols.lookupAll(fqName: (ownerPath + ["<init>"]).map { interner.intern($0) })
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [valueType] && signature.returnType == ownerType
        }, "Expected AtomicNativePtr(value: NativePtr)")
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])

        try assertMutableProperty(
            ownerPath: ownerPath,
            named: "value",
            type: valueType,
            sema: sema,
            interner: interner
        )

        let pointerMembers: [(String, [TypeID], TypeID)] = [
            ("compareAndSet", [valueType, valueType], sema.types.booleanType),
            ("compareAndSwap", [valueType, valueType], valueType),
            ("getAndSet", [valueType], valueType),
            ("toString", [], sema.types.stringType),
        ]
        for (name, parameters, returnType) in pointerMembers {
            _ = try memberFunction(
                ownerPath: ownerPath,
                named: name,
                parameterTypes: parameters,
                returnType: returnType,
                sema: sema,
                interner: interner
            )
        }
    }

    // MARK: - MutableData

    func testMutableDataSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let ownerPath = ["kotlin", "native", "concurrent", "MutableData"]
        let ownerSymbol = try symbol(ownerPath, sema: sema, interner: interner)
        let ownerType = try classType(ownerPath, sema: sema, interner: interner)
        let byteArrayType = try classType(["kotlin", "ByteArray"], sema: sema, interner: interner)
        let cOpaquePointerType = try classType(["kotlinx", "cinterop", "COpaquePointer"], sema: sema, interner: interner)
        let nullableCOpaquePointerType = sema.types.makeNullable(cOpaquePointerType)

        XCTAssertEqual(sema.symbols.symbol(ownerSymbol)?.kind, .class)
        XCTAssertTrue(
            sema.symbols.annotations(for: ownerSymbol).contains {
                $0.annotationFQName == "kotlin.Deprecated"
                    && $0.arguments.contains("level = DeprecationLevel.ERROR")
            },
            "MutableData must carry Deprecated(ERROR) metadata"
        )

        let constructors = sema.symbols.lookupAll(fqName: (ownerPath + ["<init>"]).map { interner.intern($0) })
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.intType] && signature.returnType == ownerType
        }, "Expected MutableData(capacity: Int = 16)")
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [true])

        let size = try symbol(ownerPath + ["size"], sema: sema, interner: interner)
        XCTAssertEqual(sema.symbols.propertyType(for: size), sema.types.intType)

        let appendData = try memberFunction(
            ownerPath: ownerPath,
            named: "append",
            parameterTypes: [ownerType],
            returnType: sema.types.unitType,
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(sema.symbols.functionSignature(for: appendData)?.valueParameterHasDefaultValues, [false])

        let appendPointer = try memberFunction(
            ownerPath: ownerPath,
            named: "append",
            parameterTypes: [nullableCOpaquePointerType, sema.types.intType],
            returnType: sema.types.unitType,
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(sema.symbols.functionSignature(for: appendPointer)?.valueParameterHasDefaultValues, [false, false])

        let appendByteArray = try memberFunction(
            ownerPath: ownerPath,
            named: "append",
            parameterTypes: [byteArrayType, sema.types.intType, sema.types.intType],
            returnType: sema.types.unitType,
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(sema.symbols.functionSignature(for: appendByteArray)?.valueParameterHasDefaultValues, [false, true, true])

        let copyInto = try memberFunction(
            ownerPath: ownerPath,
            named: "copyInto",
            parameterTypes: [byteArrayType, sema.types.intType, sema.types.intType, sema.types.intType],
            returnType: sema.types.unitType,
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            sema.symbols.functionSignature(for: copyInto)?.valueParameterHasDefaultValues,
            [false, false, false, false]
        )

        let get = try memberFunction(
            ownerPath: ownerPath,
            named: "get",
            parameterTypes: [sema.types.intType],
            returnType: sema.types.intType,
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(sema.symbols.symbol(get)?.flags.contains(.operatorFunction) == true)

        _ = try memberFunction(
            ownerPath: ownerPath,
            named: "reset",
            parameterTypes: [],
            returnType: sema.types.unitType,
            sema: sema,
            interner: interner
        )

        try assertMutableDataLockedMember(
            named: "withBufferLocked",
            ownerPath: ownerPath,
            ownerType: ownerType,
            blockParameterTypes: [byteArrayType, sema.types.intType],
            sema: sema,
            interner: interner
        )
        try assertMutableDataLockedMember(
            named: "withPointerLocked",
            ownerPath: ownerPath,
            ownerType: ownerType,
            blockParameterTypes: [cOpaquePointerType, sema.types.intType],
            sema: sema,
            interner: interner
        )
    }

    private func assertMutableDataLockedMember(
        named name: String,
        ownerPath: [String],
        ownerType: TypeID,
        blockParameterTypes: [TypeID],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let candidates = sema.symbols.lookupAll(fqName: (ownerPath + [name]).map { interner.intern($0) })
        let member = try XCTUnwrap(candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.receiverType == ownerType,
                  signature.parameterTypes.count == 1,
                  signature.typeParameterSymbols.count == 1,
                  signature.classTypeParameterCount == 0
            else {
                return false
            }
            let rType = sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0],
                nullability: .nonNull
            )))
            guard signature.returnType == rType,
                  case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes[0])
            else {
                return false
            }
            return blockType.params == blockParameterTypes && blockType.returnType == rType
        }, "Expected MutableData.\(name)<R>", file: file, line: line)
        XCTAssertEqual(sema.symbols.functionSignature(for: member)?.valueParameterHasDefaultValues, [false], file: file, line: line)
    }

    // MARK: - FreezableAtomicReference<T>

    func testFreezableAtomicReferenceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let ownerPath = ["kotlin", "native", "concurrent", "FreezableAtomicReference"]
        let ownerSymbol = try symbol(ownerPath, sema: sema, interner: interner)
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: ownerSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let ownerType = sema.types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(ownerSymbol)?.kind, .class)
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: ownerSymbol).count, 1)
        XCTAssertTrue(
            sema.symbols.annotations(for: ownerSymbol).contains {
                $0.annotationFQName == "kotlin.Deprecated"
                    && $0.arguments.contains("level = DeprecationLevel.ERROR")
            },
            "FreezableAtomicReference must carry Deprecated(ERROR) metadata"
        )

        let constructors = sema.symbols.lookupAll(fqName: (ownerPath + ["<init>"]).map { interner.intern($0) })
        let constructor = try XCTUnwrap(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [typeParameterType] && signature.returnType == ownerType
        }, "Expected FreezableAtomicReference(value: T)")
        let constructorSignature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))
        XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), "kk_freezable_atomic_ref_create")
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(constructorSignature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(constructorSignature.classTypeParameterCount, 1)

        try assertMutableProperty(
            ownerPath: ownerPath,
            named: "value",
            type: typeParameterType,
            sema: sema,
            interner: interner
        )
        let valueProperty = try symbol(ownerPath + ["value"], sema: sema, interner: interner)
        XCTAssertEqual(sema.symbols.externalLinkName(for: valueProperty), "kk_freezable_atomic_ref_load")

        let members: [(String, [TypeID], TypeID, String?)] = [
            (
                "compareAndSet",
                [typeParameterType, typeParameterType],
                sema.types.booleanType,
                "kk_freezable_atomic_ref_compareAndSet"
            ),
            (
                "compareAndSwap",
                [typeParameterType, typeParameterType],
                typeParameterType,
                "kk_freezable_atomic_ref_compareAndSwap"
            ),
        ]
        for (name, parameters, returnType, linkName) in members {
            let candidates = sema.symbols.lookupAll(fqName: (ownerPath + [name]).map { interner.intern($0) })
            let member = try XCTUnwrap(candidates.first { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType == ownerType
                    && signature.parameterTypes == parameters
                    && signature.returnType == returnType
                    && signature.typeParameterSymbols == [typeParameter]
                    && signature.classTypeParameterCount == 1
            }, "Expected FreezableAtomicReference.\(name)")
            if let linkName {
                XCTAssertEqual(sema.symbols.externalLinkName(for: member), linkName)
            }
        }

        let toStringCandidates = sema.symbols.lookupAll(fqName: (ownerPath + ["toString"]).map { interner.intern($0) })
        let toString = try XCTUnwrap(toStringCandidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == []
                && signature.returnType == sema.types.stringType
        }, "Expected FreezableAtomicReference.toString")
        XCTAssertTrue(sema.symbols.symbol(toString)?.flags.contains(.overrideMember) == true)
    }

    // MARK: - AtomicReference<T> (legacy kotlin.native.concurrent)

    func testLegacyAtomicReferenceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "AtomicReference"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.AtomicReference to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)

        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)
        XCTAssertEqual(typeParams.count, 1)
    }

    func testLegacyAtomicReferenceConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let atomicRefFQName = ["kotlin", "native", "concurrent", "AtomicReference"].map { interner.intern($0) }
        let initFQName = atomicRefFQName + [interner.intern("<init>")]
        let initMethods = sema.symbols.lookupAll(fqName: initFQName)
        XCTAssertFalse(initMethods.isEmpty, "Expected AtomicReference <init> to be registered")

        let initMethod = try XCTUnwrap(initMethods.first)
        XCTAssertEqual(sema.symbols.externalLinkName(for: initMethod), "kk_native_atomic_ref_create")

        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: initMethod))
        XCTAssertEqual(sig.parameterTypes.count, 1)
        XCTAssertNil(sig.receiverType, "Constructor should have no receiver type")
    }

    func testLegacyAtomicReferenceValuePropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let atomicRefFQName = ["kotlin", "native", "concurrent", "AtomicReference"].map { interner.intern($0) }
        let propFQName = atomicRefFQName + [interner.intern("value")]
        let propSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: propFQName))
        XCTAssertEqual(sema.symbols.externalLinkName(for: propSymbol), "kk_native_atomic_ref_load")
    }

    func testLegacyAtomicReferenceCompareAndSwapIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let atomicRefFQName = ["kotlin", "native", "concurrent", "AtomicReference"].map { interner.intern($0) }
        let methodFQName = atomicRefFQName + [interner.intern("compareAndSwap")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        XCTAssertFalse(methods.isEmpty, "Expected AtomicReference.compareAndSwap to be registered")

        let method = try XCTUnwrap(methods.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: method))
        XCTAssertEqual(sig.parameterTypes.count, 2)
        XCTAssertEqual(sema.symbols.externalLinkName(for: method), "kk_native_atomic_ref_compareAndSwap")
    }

    func testLegacyAtomicReferenceCompareAndSetIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let atomicRefFQName = ["kotlin", "native", "concurrent", "AtomicReference"].map { interner.intern($0) }
        let methodFQName = atomicRefFQName + [interner.intern("compareAndSet")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        XCTAssertFalse(methods.isEmpty, "Expected AtomicReference.compareAndSet to be registered")

        let method = try XCTUnwrap(methods.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: method))
        XCTAssertEqual(sig.parameterTypes.count, 2)
        XCTAssertEqual(sig.returnType, sema.types.booleanType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: method), "kk_native_atomic_ref_compareAndSet")
    }

    // MARK: - @SharedImmutable annotation

    func testSharedImmutableAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "SharedImmutable"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.SharedImmutable annotation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol)
        let targetAnnotation = annotations.first { $0.annotationFQName == "kotlin.annotation.Target" }
        XCTAssertNotNil(targetAnnotation, "Expected @Target annotation on @SharedImmutable")
        XCTAssertEqual(
            Set(targetAnnotation?.arguments ?? []),
            ["AnnotationTarget.PROPERTY"],
            "Expected only PROPERTY target for @SharedImmutable"
        )
    }

    func testSharedImmutableAnnotationResolvesOnProperty() throws {
        let source = """
        import kotlin.native.concurrent.SharedImmutable

        @SharedImmutable
        val globalData: Int = 42
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "@SharedImmutable on top-level property should resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testSharedImmutableAnnotationTargetErrorOnFunction() throws {
        // @SharedImmutable is only valid on PROPERTY, not on functions.
        // The AnnotationTargetValidation phase should emit KSWIFTK-SEMA-ANNOTATION-TARGET.
        let source = """
        import kotlin.native.concurrent.SharedImmutable

        @SharedImmutable
        fun badUsage(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        XCTAssertEqual(
            diagnostics.count, 1,
            "Expected one annotation-target diagnostic for @SharedImmutable on fun, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testSharedImmutableFieldUseSiteTargetIsRejected() throws {
        let source = """
        import kotlin.native.concurrent.SharedImmutable

        class Box {
            @field:SharedImmutable
            val value: Int = 1
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        XCTAssertEqual(
            diagnostics.count, 1,
            "Expected one annotation-target diagnostic for @field:SharedImmutable, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - @ThreadLocal (kotlin.native.concurrent) annotation

    func testNativeThreadLocalAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "ThreadLocal"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.ThreadLocal annotation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol)
        let targetAnnotation = annotations.first { $0.annotationFQName == "kotlin.annotation.Target" }
        XCTAssertNotNil(targetAnnotation, "Expected @Target annotation on native @ThreadLocal")
        XCTAssertEqual(
            Set(targetAnnotation?.arguments ?? []),
            ["AnnotationTarget.PROPERTY", "AnnotationTarget.CLASS"],
            "Expected PROPERTY and CLASS targets for native @ThreadLocal"
        )
    }

    func testNativeThreadLocalAnnotationResolvesOnProperty() throws {
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        @ThreadLocal
        var counter: Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "@ThreadLocal on top-level property should resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testNativeThreadLocalAnnotationResolvesOnClass() throws {
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        @ThreadLocal
        class LocalState
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "@ThreadLocal on class should resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func testNativeThreadLocalAnnotationTargetErrorOnFunction() throws {
        // @ThreadLocal (native) is only valid on PROPERTY/FIELD, not on functions.
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        @ThreadLocal
        fun badUsage(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        XCTAssertEqual(
            diagnostics.count, 1,
            "Expected one annotation-target diagnostic for native @ThreadLocal on fun, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testNativeThreadLocalFieldUseSiteTargetIsRejected() throws {
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        class Box {
            @field:ThreadLocal
            val value: Int = 1
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        XCTAssertEqual(
            diagnostics.count, 1,
            "Expected one annotation-target diagnostic for @field:ThreadLocal, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - @ObsoleteWorkersApi annotation

    func testObsoleteWorkersApiAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "native", "concurrent", "ObsoleteWorkersApi"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.ObsoleteWorkersApi annotation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol)
        let requiresOptIn = annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" }
        XCTAssertEqual(
            Set(requiresOptIn?.arguments ?? []),
            [
                "message = \"Workers API is obsolete and will be replaced with threads eventually\"",
                "level = RequiresOptIn.Level.WARNING",
            ]
        )

        let targetAnnotation = annotations.first { $0.annotationFQName == "kotlin.annotation.Target" }
        XCTAssertEqual(
            Set(targetAnnotation?.arguments ?? []),
            [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ]
        )
    }

    // MARK: - Package existence

    func testNativeConcurrentPackageIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let pkgFQName = ["kotlin", "native", "concurrent"].map { interner.intern($0) }
        let pkgSymbol = sema.symbols.lookup(fqName: pkgFQName)
        XCTAssertNotNil(pkgSymbol, "Expected kotlin.native.concurrent package to be registered")
        XCTAssertEqual(sema.symbols.symbol(try XCTUnwrap(pkgSymbol))?.kind, .package)
    }
}
