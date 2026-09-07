#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - kotlin.native.concurrent sema / diagnostics coverage (STDLIB-NATIVE-CONCURRENT-002)

@Suite
struct NativeConcurrentSyntheticStubTests {

    // MARK: Helpers

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
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
        interner: StringInterner
    ) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: path.map { interner.intern($0) })
        return try requireTestValue(found, "Expected \(path.joined(separator: ".")) to be registered")
    }

    private func classType(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner,
        args: [TypeArg] = [],
        nullability: Nullability = .nonNull
    ) throws -> TypeID {
        let classSymbol = try symbol(path, sema: sema, interner: interner)
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: args,
            nullability: nullability
        )))
    }

    private func cOpaquePointerType(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let aliasSymbol = try symbol(
            ["kotlinx", "cinterop", "COpaquePointer"],
            sema: sema,
            interner: interner
        )
        return try #require(
            sema.symbols.typeAliasUnderlyingType(for: aliasSymbol),
            "Expected kotlinx.cinterop.COpaquePointer to have an underlying typealias type"
        )
    }

    private func memberFunction(
        ownerPath: [String],
        named name: String,
        parameterTypes: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        let ownerType = try classType(ownerPath, sema: sema, interner: interner)
        let functionFQName = (ownerPath + [name]).map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: functionFQName)
        return try #require(candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }, "Expected \(ownerPath.joined(separator: ".")).\(name)")
    }
    private func nativeContinuationInvokerType(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let nullableCOpaquePointerType = sema.types.makeNullable(try cOpaquePointerType(
            sema: sema,
            interner: interner
        ))
        let invokerCallbackType = sema.types.make(.functionType(FunctionType(
            params: [nullableCOpaquePointerType],
            returnType: sema.types.unitType
        )))
        let cFunctionType = try classType(
            ["kotlinx", "cinterop", "CFunction"],
            sema: sema,
            interner: interner,
            args: [.invariant(invokerCallbackType)]
        )
        return try classType(
            ["kotlinx", "cinterop", "CPointer"],
            sema: sema,
            interner: interner,
            args: [.invariant(cFunctionType)]
        )
    }

    // MARK: - TransferMode enum

    @Test
    func testTransferModeEnumIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "TransferMode"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.TransferMode to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .enumClass)
    }

    @Test
    func testTransferModeSafeEntryHasCorrectType() throws {
        let (sema, interner) = try sharedSema()

        let enumFQName = ["kotlin", "native", "concurrent", "TransferMode"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let safeFQName = enumFQName + [interner.intern("SAFE")]
        let safeSymbol = try #require(
            sema.symbols.lookup(fqName: safeFQName),
            "Expected TransferMode.SAFE entry"
        )
        #expect(sema.symbols.propertyType(for: safeSymbol) == enumType)
    }

    @Test
    func testTransferModeUnsafeEntryHasCorrectType() throws {
        let (sema, interner) = try sharedSema()

        let enumFQName = ["kotlin", "native", "concurrent", "TransferMode"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let unsafeFQName = enumFQName + [interner.intern("UNSAFE")]
        let unsafeSymbol = try #require(sema.symbols.lookup(fqName: unsafeFQName))
        #expect(sema.symbols.propertyType(for: unsafeSymbol) == enumType)
    }

    @Test
    func testTransferModeResolvesInSource() {
        let source = """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

        import kotlin.native.concurrent.TransferMode

        fun probe(): TransferMode = TransferMode.SAFE
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected TransferMode.SAFE to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testTransferModeIsBackedByBundledSource() throws {
        let (sema, interner) = try sharedSema()

        let transferMode = try symbol(
            ["kotlin", "native", "concurrent", "TransferMode"],
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.sourceFileID(for: transferMode) != nil)
        #expect(!sema.symbols.symbol(transferMode)!.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(transferMode))
    }

    @Test
    func testTransferModeFourAPIsResolveWithExactTypes() {
        let source = """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

        import kotlin.native.concurrent.TransferMode

        fun entries(): kotlin.enums.EnumEntries<TransferMode> = TransferMode.entries
        fun value(): Int = TransferMode.SAFE.value
        fun valueOf(): TransferMode = TransferMode.valueOf("UNSAFE")
        fun values(): Array<TransferMode> = TransferMode.values()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected TransferMode APIs to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - FutureState enum

    @Test
    func testFutureStateEnumIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "FutureState"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.FutureState to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .enumClass)
    }

    @Test
    func testFutureStateEntriesAreRegistered() throws {
        let (sema, interner) = try sharedSema()

        let baseFQName = ["kotlin", "native", "concurrent", "FutureState"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: baseFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entry in ["INVALID", "SCHEDULED", "COMPUTED", "CANCELLED", "THROWN"] {
            let entryFQName = baseFQName + [interner.intern(entry)]
            let entrySymbol = try #require(
                sema.symbols.lookup(fqName: entryFQName),
                "Expected FutureState.\(entry) to be registered"
            )
            #expect(sema.symbols.propertyType(for: entrySymbol) == enumType)
        }
    }

    @Test
    func testFutureStateIsBackedByBundledSource() throws {
        let (sema, interner) = try sharedSema()

        let futureState = try symbol(
            ["kotlin", "native", "concurrent", "FutureState"],
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.sourceFileID(for: futureState) != nil)
        #expect(!sema.symbols.symbol(futureState)!.flags.contains(.synthetic))
    }

    @Test
    func testFutureStateFourAPIsResolveWithExactTypes() throws {
        let source = """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

        import kotlin.native.concurrent.FutureState

        fun entries(): kotlin.enums.EnumEntries<FutureState> = FutureState.entries
        fun value(): Int = FutureState.COMPUTED.value
        fun valueOf(): FutureState = FutureState.valueOf("THROWN")
        fun values(): Array<FutureState> = FutureState.values()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected FutureState APIs to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    // MARK: - Continuation0 / Continuation1 / Continuation2 classes

    @Test
    func testContinuationTypesAreRegistered() throws {
        let (sema, interner) = try sharedSema()

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

            #expect(sema.symbols.symbol(continuation)?.kind == .class)
            #expect(sema.types.nominalTypeParameterSymbols(for: continuation).count == arity)
            #expect(sema.symbols.directSupertypes(for: continuation).contains(functionSupertype))
            #expect(
                sema.symbols.annotations(for: continuation).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "\(name) must carry Deprecated metadata"
            )
        }
    }

    @Test
    func testContinuationConstructorsAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let invokerType = try nativeContinuationInvokerType(sema: sema, interner: interner)

        for (name, arity) in [("Continuation0", 0), ("Continuation1", 1), ("Continuation2", 2)] {
            let continuationFQName = ["kotlin", "native", "concurrent", name].map { interner.intern($0) }
            let continuation = try #require(sema.symbols.lookup(fqName: continuationFQName))
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
            let constructor = try #require(constructors.first { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.parameterTypes == [blockType, invokerType, sema.types.booleanType]
                    && signature.returnType == continuationType
            }, "Expected \(name) constructor")
            let signature = try #require(sema.symbols.functionSignature(for: constructor))

            #expect(sema.symbols.symbol(constructor)?.kind == .constructor)
            #expect(signature.valueParameterHasDefaultValues == [false, false, true])
            #expect(signature.typeParameterSymbols == typeParameters)
            #expect(signature.classTypeParameterCount == arity)
        }
    }

    @Test
    func testContinuationMembersAreRegistered() throws {
        let (sema, interner) = try sharedSema()

        for (name, arity) in [("Continuation0", 0), ("Continuation1", 1), ("Continuation2", 2)] {
            let continuationFQName = ["kotlin", "native", "concurrent", name].map { interner.intern($0) }
            let continuation = try #require(sema.symbols.lookup(fqName: continuationFQName))
            let typeParameters = sema.types.nominalTypeParameterSymbols(for: continuation)
            let typeParameterTypes = typeParameters.map {
                sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))
            }
            let continuationType = sema.types.make(.classType(ClassType(
                classSymbol: continuation,
                args: typeParameterTypes.map { .invariant($0) },
                nullability: .nonNull
            )))

            let dispose = try #require(
                sema.symbols.lookupAll(fqName: continuationFQName + [interner.intern("dispose")]).first,
                "Expected \(name).dispose"
            )
            let disposeSignature = try #require(sema.symbols.functionSignature(for: dispose))
            #expect(disposeSignature.receiverType == continuationType)
            #expect(disposeSignature.parameterTypes == [])
            #expect(disposeSignature.returnType == sema.types.unitType)
            #expect(disposeSignature.classTypeParameterCount == arity)

            let invoke = try #require(
                sema.symbols.lookupAll(fqName: continuationFQName + [interner.intern("invoke")]).first,
                "Expected \(name).invoke"
            )
            let invokeSignature = try #require(sema.symbols.functionSignature(for: invoke))
            #expect(invokeSignature.receiverType == continuationType)
            #expect(invokeSignature.parameterTypes == typeParameterTypes)
            #expect(invokeSignature.returnType == sema.types.unitType)
            #expect(invokeSignature.classTypeParameterCount == arity)
            #expect(sema.symbols.symbol(invoke)?.flags.contains(.operatorFunction) == true)
            #expect(sema.symbols.symbol(invoke)?.flags.contains(.overrideMember) == true)
        }
    }

    @Test
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
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected Continuation types to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testCallContinuationFunctionsAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let receiverType = try cOpaquePointerType(
            sema: sema,
            interner: interner
        )

        for arity in 0...2 {
            let functionFQName = ["kotlin", "native", "concurrent", "callContinuation\(arity)"]
                .map { interner.intern($0) }
            let function = try #require(sema.symbols.lookupAll(fqName: functionFQName).first { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.unitType
                    && signature.typeParameterSymbols.count == arity
            }, "Expected callContinuation\(arity)")
            let signature = try #require(sema.symbols.functionSignature(for: function))

            #expect(sema.symbols.symbol(function)?.kind == .function)
            #expect(signature.classTypeParameterCount == 0)
            #expect(signature.valueParameterHasDefaultValues == [])
            #expect(
                sema.symbols.annotations(for: function).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "callContinuation\(arity) must carry Deprecated metadata"
            )
        }
    }

    @Test
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
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected callContinuation functions to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }
    // MARK: - FreezingException class

    @Test
    func testFreezingExceptionClassIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let freezingException = try symbol(
            ["kotlin", "native", "concurrent", "FreezingException"],
            sema: sema,
            interner: interner
        )
        let runtimeException = try symbol(["kotlin", "RuntimeException"], sema: sema, interner: interner)

        #expect(sema.symbols.symbol(freezingException)?.kind == .class)
        #expect(sema.symbols.symbol(freezingException)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.sourceFileID(for: freezingException) != nil)
        #expect(sema.symbols.directSupertypes(for: freezingException).contains(runtimeException))
        let annotationNames = sema.symbols.annotations(for: freezingException).map(\.annotationFQName)
        #expect(
            annotationNames.contains("Deprecated"),
            "FreezingException must carry Deprecated metadata: \(annotationNames)"
        )
        #expect(
            annotationNames.contains("DeprecatedSinceKotlin"),
            "FreezingException must carry DeprecatedSinceKotlin metadata: \(annotationNames)"
        )
    }

    @Test
    func testFreezingExceptionConstructorIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let exceptionFQName = ["kotlin", "native", "concurrent", "FreezingException"]
            .map { interner.intern($0) }
        let exception = try #require(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exception,
            args: [],
            nullability: .nonNull
        )))

        let constructors = sema.symbols.lookupAll(fqName: exceptionFQName + [interner.intern("<init>")])
        let constructor = try #require(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.anyType, sema.types.anyType]
                && signature.returnType == exceptionType
        })
        let signature = try #require(sema.symbols.functionSignature(for: constructor))

        #expect(sema.symbols.symbol(constructor)?.kind == .constructor)
        #expect(signature.valueParameterHasDefaultValues == [false, false])
        #expect(sema.symbols.externalLinkName(for: constructor) == "__kk_freezing_exception_new")
    }

    @Test
    func testFreezingExceptionResolvesInSource() {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")
        import kotlin.native.concurrent.FreezingException

        fun probe(toFreeze: Any, blocker: Any): RuntimeException =
            FreezingException(toFreeze, blocker)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected FreezingException constructor to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    // MARK: - InvalidMutabilityException class

    @Test
    func testInvalidMutabilityExceptionClassIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let invalidMutabilityException = try symbol(
            ["kotlin", "native", "concurrent", "InvalidMutabilityException"],
            sema: sema,
            interner: interner
        )
        let runtimeException = try symbol(["kotlin", "RuntimeException"], sema: sema, interner: interner)

        #expect(sema.symbols.symbol(invalidMutabilityException)?.kind == .class)
        #expect(sema.symbols.directSupertypes(for: invalidMutabilityException).contains(runtimeException))
        #expect(
            sema.symbols.annotations(for: invalidMutabilityException).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            },
            "InvalidMutabilityException must carry ExperimentalNativeApi metadata"
        )
    }

    @Test
    func testInvalidMutabilityExceptionConstructorIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let exceptionFQName = ["kotlin", "native", "concurrent", "InvalidMutabilityException"]
            .map { interner.intern($0) }
        let exception = try #require(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exception,
            args: [],
            nullability: .nonNull
        )))

        let constructors = sema.symbols.lookupAll(fqName: exceptionFQName + [interner.intern("<init>")])
        let constructor = try #require(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == exceptionType
        })
        let signature = try #require(sema.symbols.functionSignature(for: constructor))

        #expect(sema.symbols.symbol(constructor)?.kind == .constructor)
        #expect(signature.receiverType == nil)
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(
            sema.symbols.externalLinkName(for: constructor)
                == "__kk_invalid_mutability_exception_new_message"
        )
    }

    @Test
    func testInvalidMutabilityExceptionResolvesInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.concurrent.InvalidMutabilityException

        fun probe(message: String): RuntimeException =
            InvalidMutabilityException(message)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected InvalidMutabilityException constructor to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    // MARK: - Worker class

    @Test
    func testWorkerClassIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.Worker to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .class)
    }

    @Test
    func testWorkerTopLevelNominalSurfaceMatchesKotlinNative() throws {
        let (sema, interner) = try sharedSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let workerSymbol = try #require(sema.symbols.lookup(fqName: workerFQName))
        let workerInfo = try #require(sema.symbols.symbol(workerSymbol))
        let workerType = try #require(sema.symbols.propertyType(for: workerSymbol))

        #expect(workerInfo.visibility == .public)
        #expect(workerInfo.flags.contains(.valueType))
        #expect(!workerInfo.flags.contains(.openType))
        #expect(sema.symbols.valueClassUnderlyingType(for: workerSymbol) == sema.types.intType)
        #expect(sema.symbols.annotations(for: workerSymbol).contains {
            $0.annotationFQName == "kotlin.native.concurrent.ObsoleteWorkersApi"
        })

        let constructorFQName = workerFQName + [interner.intern("<init>")]
        let constructor = try #require(
            sema.symbols.lookupAll(fqName: constructorFQName).first { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return signature.parameterTypes == [sema.types.intType]
                    && signature.returnType == workerType
            }
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(constructorInfo.visibility == .internal)
        #expect(constructorSignature.receiverType == nil)
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])
        #expect(constructorSignature.valueParameterSymbols.count == 1)
        #expect(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0])?.name == interner.intern("id"))
        #expect(sema.symbols.annotations(for: constructor).contains {
            $0.annotationFQName == "kotlin.PublishedApi"
        })

        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: workerSymbol))
        let companionInfo = try #require(sema.symbols.symbol(companionSymbol))
        #expect(companionInfo.kind == .object)
        #expect(companionInfo.visibility == .public)
        #expect(sema.symbols.parentSymbol(for: companionSymbol) == workerSymbol)
        #expect(sema.symbols.propertyType(for: companionSymbol) != nil)
    }

    @Test
    func testWorkerExecuteIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let workerSymbol = try #require(sema.symbols.lookup(fqName: workerFQName))
        let workerType = try #require(sema.symbols.propertyType(for: workerSymbol))
        let transferModeType = try classType(
            ["kotlin", "native", "concurrent", "TransferMode"],
            sema: sema,
            interner: interner
        )

        let methodFQName = workerFQName + [interner.intern("execute")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        #expect(!methods.isEmpty, "Expected Worker.execute to be registered")

        let method = try #require(methods.first)
        let signature = try #require(sema.symbols.functionSignature(for: method))
        #expect(signature.typeParameterSymbols.count == 2)

        let t1 = sema.types.make(.typeParam(TypeParamType(
            symbol: signature.typeParameterSymbols[0],
            nullability: .nonNull
        )))
        let t2 = sema.types.make(.typeParam(TypeParamType(
            symbol: signature.typeParameterSymbols[1],
            nullability: .nonNull
        )))
        let producerType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: t1
        )))
        let jobType = sema.types.make(.functionType(FunctionType(
            params: [t1],
            returnType: t2
        )))
        let futureT2Type = try classType(
            ["kotlin", "native", "concurrent", "Future"],
            sema: sema,
            interner: interner,
            args: [.invariant(t2)]
        )

        #expect(signature.receiverType == workerType)
        #expect(signature.parameterTypes == [transferModeType, producerType, jobType])
        #expect(signature.returnType == futureT2Type)
        #expect(signature.valueParameterHasDefaultValues == [false, false, false])
        #expect(sema.symbols.externalLinkName(for: method) == "kk_worker_execute")
    }

    @Test
    func testWorkerRequestTerminationIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let workerSymbol = try #require(sema.symbols.lookup(fqName: workerFQName))

        let methodFQName = workerFQName + [interner.intern("requestTermination")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        #expect(!methods.isEmpty, "Expected Worker.requestTermination to be registered")

        let method = try #require(methods.first)
        let sig = try #require(sema.symbols.functionSignature(for: method))
        #expect(sig.parameterTypes == [sema.types.booleanType])
        let futureBooleanType = try classType(
            ["kotlin", "native", "concurrent", "Future"],
            sema: sema,
            interner: interner,
            args: [.invariant(sema.types.booleanType)]
        )
        #expect(sig.returnType == futureBooleanType)
        #expect(sig.valueParameterHasDefaultValues == [true])

        let workerType = try #require(sema.symbols.propertyType(for: workerSymbol))
        #expect(sig.receiverType == workerType)
        #expect(sema.symbols.externalLinkName(for: method) == "kk_worker_request_termination")
    }

    @Test
    func testWorkerExecuteAndRequestTerminationResolveInSource() {
        let source = """
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker

        fun probe(worker: Worker): Int {
            val future = worker.execute(TransferMode.SAFE, { 21 }) { it * 2 }
            val stopped: Boolean = worker.requestTermination(false).result
            return if (stopped) future.result else 0
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected Worker.execute and requestTermination to resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testWorkerIsTerminatedPropertyIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let propFQName = workerFQName + [interner.intern("isTerminated")]
        let propSymbol = try #require(
            sema.symbols.lookup(fqName: propFQName),
            "Expected Worker.isTerminated property"
        )
        #expect(sema.symbols.propertyType(for: propSymbol) == sema.types.booleanType)
        #expect(sema.symbols.externalLinkName(for: propSymbol) == "kk_worker_is_terminated")
    }

    @Test
    func testWorkerNamePropertyIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let workerFQName = ["kotlin", "native", "concurrent", "Worker"].map { interner.intern($0) }
        let propFQName = workerFQName + [interner.intern("name")]
        let propSymbol = try #require(
            sema.symbols.lookup(fqName: propFQName),
            "Expected Worker.name property"
        )
        #expect(sema.symbols.propertyType(for: propSymbol) == sema.types.stringType)
        #expect(sema.symbols.externalLinkName(for: propSymbol) == "kk_worker_name")
    }

    @Test
    func testWorkerCompanionStartIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let companionFQName = ["kotlin", "native", "concurrent", "Worker", "Companion"]
            .map { interner.intern($0) }
        let startFQName = companionFQName + [interner.intern("start")]
        let methods = sema.symbols.lookupAll(fqName: startFQName)
        #expect(!methods.isEmpty, "Expected Worker.Companion.start to be registered")

        let method = try #require(methods.first)
        let sig = try #require(sema.symbols.functionSignature(for: method))
        #expect(sig.parameterTypes == [sema.types.makeNullable(sema.types.stringType)])
        #expect(sig.valueParameterHasDefaultValues == [true])
        #expect(sema.symbols.externalLinkName(for: method) == "kk_worker_new")
    }

    // MARK: - Future<T> class

    @Test
    func testFutureClassIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.Future to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .class)

        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)
        #expect(typeParams.count == 1)
    }

    @Test
    func testFutureResultPropertyIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let propFQName = futureFQName + [interner.intern("result")]
        let propSymbol = try #require(
            sema.symbols.lookup(fqName: propFQName),
            "Expected Future.result property"
        )
        #expect(sema.symbols.externalLinkName(for: propSymbol) == "kk_future_result")
    }

    @Test
    func testFutureConsumeMethodIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let methodFQName = futureFQName + [interner.intern("consume")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        #expect(!methods.isEmpty, "Expected Future.consume to be registered")

        let method = try #require(methods.first)
        let sig = try #require(sema.symbols.functionSignature(for: method))
        #expect(sig.parameterTypes == [])
        #expect(sema.symbols.externalLinkName(for: method) == "kk_future_consume")
    }

    @Test
    func testFutureGetStateMethodIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let futureFQName = ["kotlin", "native", "concurrent", "Future"].map { interner.intern($0) }
        let methodFQName = futureFQName + [interner.intern("getState")]
        let methods = sema.symbols.lookupAll(fqName: methodFQName)
        #expect(!methods.isEmpty, "Expected Future.getState to be registered")

        let method = try #require(methods.first)
        let sig = try #require(sema.symbols.functionSignature(for: method))
        #expect(sig.parameterTypes == [])

        let futureStateFQName = ["kotlin", "native", "concurrent", "FutureState"].map { interner.intern($0) }
        let futureStateSymbol = try #require(sema.symbols.lookup(fqName: futureStateFQName))
        let futureStateType = sema.types.make(.classType(ClassType(
            classSymbol: futureStateSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sig.returnType == futureStateType)
        #expect(sema.symbols.externalLinkName(for: method) == "kk_future_getState")
    }
    // MARK: - @SharedImmutable annotation

    @Test
    func testSharedImmutableAnnotationIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "SharedImmutable"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.SharedImmutable annotation to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
        #expect(
            sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false,
            "SharedImmutable should be provided by bundled Kotlin source"
        )

        let annotations = sema.symbols.annotations(for: symbol)
        let targetAnnotation = annotations.first { $0.annotationFQName == "Target" }
        #expect(targetAnnotation != nil, "Expected @Target annotation on @SharedImmutable")
        let targetArguments = targetAnnotation?.arguments ?? []
        #expect(
            Set(targetArguments) == ["AnnotationTarget.PROPERTY"],
            "Expected only PROPERTY target for @SharedImmutable"
        )

        #expect(annotations.contains { $0.annotationFQName == "Deprecated" })
        #expect(annotations.contains {
            $0.annotationFQName == "DeprecatedSinceKotlin"
                && $0.arguments.contains { $0.contains("errorSince") && $0.contains("2.1") }
        })

        let constructor = try #require(
            sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            },
            "Expected SharedImmutable to expose a public implicit no-arg constructor"
        )
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(signature.parameterTypes.isEmpty)
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
    }

    @Test
    func testSharedImmutableAnnotationResolvesOnProperty() {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")

        import kotlin.native.concurrent.SharedImmutable

        @SharedImmutable
        val globalData: Int = 42
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "@SharedImmutable on top-level property should resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testSharedImmutableAnnotationTargetErrorOnFunction() {
        // @SharedImmutable is only valid on PROPERTY, not on functions.
        // The AnnotationTargetValidation phase should emit KSWIFTK-SEMA-ANNOTATION-TARGET.
        let source = """
        @file:Suppress("DEPRECATION_ERROR")

        import kotlin.native.concurrent.SharedImmutable

        @SharedImmutable
        fun badUsage(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET"
        }
        #expect(
            diagnostics.count == 1,
            "Expected one annotation-target diagnostic for @SharedImmutable on fun, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testSharedImmutableFieldUseSiteTargetIsRejected() {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")

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
        #expect(
            diagnostics.count == 1,
            "Expected one annotation-target diagnostic for @field:SharedImmutable, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - @ThreadLocal (kotlin.native.concurrent) annotation

    @Test
    func testNativeThreadLocalAnnotationIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "ThreadLocal"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.ThreadLocal annotation to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol)
        let targetAnnotation = annotations.first { $0.annotationFQName == "kotlin.annotation.Target" }
        #expect(targetAnnotation != nil, "Expected @Target annotation on native @ThreadLocal")
        let targetArguments = targetAnnotation?.arguments ?? []
        #expect(
            Set(targetArguments) == ["AnnotationTarget.PROPERTY", "AnnotationTarget.CLASS"],
            "Expected PROPERTY and CLASS targets for native @ThreadLocal"
        )
    }

    @Test
    func testNativeThreadLocalAnnotationHasNoArgConstructor() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "ThreadLocal"].map { interner.intern($0) }
        let annotationSymbol = try #require(sema.symbols.lookup(fqName: fqName))
        let annotationType = sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let constructorSymbol = try #require(
            sema.symbols.lookup(fqName: fqName + [interner.intern("<init>")]),
            "Expected kotlin.native.concurrent.ThreadLocal.<init> to be registered"
        )
        let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(sema.symbols.symbol(constructorSymbol)?.kind == .constructor)
        #expect(signature.receiverType == nil)
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.returnType == annotationType)
        #expect(sema.symbols.externalLinkName(for: constructorSymbol) == nil)
    }

    @Test
    func testNativeThreadLocalAnnotationConstructorResolvesInSource() throws {
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        fun construct(): Any? = ThreadLocal()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "ThreadLocal() should resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testNativeThreadLocalAnnotationResolvesOnProperty() {
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        @ThreadLocal
        var counter: Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "@ThreadLocal on top-level property should resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testNativeThreadLocalAnnotationResolvesOnClass() {
        let source = """
        import kotlin.native.concurrent.ThreadLocal

        @ThreadLocal
        class LocalState
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!(
            ctx.diagnostics.hasError
        ), "@ThreadLocal on class should resolve cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testNativeThreadLocalAnnotationTargetErrorOnFunction() {
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
        #expect(
            diagnostics.count == 1,
            "Expected one annotation-target diagnostic for native @ThreadLocal on fun, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testNativeThreadLocalFieldUseSiteTargetIsRejected() {
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
        #expect(
            diagnostics.count == 1,
            "Expected one annotation-target diagnostic for @field:ThreadLocal, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - @ObsoleteWorkersApi annotation

    @Test
    func testObsoleteWorkersApiAnnotationIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fqName = ["kotlin", "native", "concurrent", "ObsoleteWorkersApi"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.concurrent.ObsoleteWorkersApi annotation to be registered"
        )
        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol)
        let requiresOptIn = annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" }
        let requiresOptInArgs = requiresOptIn?.arguments ?? []
        #expect(
            Set(requiresOptInArgs) == [
                "message = \"Workers API is obsolete and will be replaced with threads eventually\"",
                "level = RequiresOptIn.Level.WARNING",
            ]
        )

        let targetAnnotation = annotations.first { $0.annotationFQName == "kotlin.annotation.Target" }
        let targetArgs = targetAnnotation?.arguments ?? []
        #expect(
            Set(targetArgs) == [
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
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            }
        )
        #expect(annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" })
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.SinceKotlin"
                    && $0.arguments == ["version = \"1.9\""]
            }
        )

        let annotationType = sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        let constructors = sema.symbols.lookupAll(
            fqName: fqName + [interner.intern("<init>")]
        ).filter { sema.symbols.symbol($0)?.kind == .constructor }
        #expect(constructors.count == 1)
        let constructor = try #require(
            constructors.first,
            "Expected kotlin.native.concurrent.ObsoleteWorkersApi() constructor"
        )
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(sema.symbols.symbol(constructor)?.visibility == .public)
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.returnType == annotationType)
    }

    // MARK: - Package existence

    @Test
    func testNativeConcurrentPackageIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let pkgFQName = ["kotlin", "native", "concurrent"].map { interner.intern($0) }
        let pkgSymbol = sema.symbols.lookup(fqName: pkgFQName)
        #expect(pkgSymbol != nil, "Expected kotlin.native.concurrent package to be registered")
        #expect(sema.symbols.symbol(try #require(pkgSymbol))?.kind == .package)
    }
}
#endif
