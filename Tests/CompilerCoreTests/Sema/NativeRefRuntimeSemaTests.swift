/// STDLIB-NATIVE-REF-002: Sema-level tests for `kotlin.native.ref` and
/// `kotlin.native.runtime` exposure.
///
/// Verifies:
/// 1. Name resolution — all symbols are registered and look-uppable.
/// 2. Signature visibility — member signatures have the expected shape.
/// 3. Opt-in requirements — symbols carry their expected native opt-in marker
///    annotations so diagnostics fire.

@testable import CompilerCore
import Foundation
import XCTest

final class NativeRefRuntimeSemaTests: XCTestCase {
    // MARK: - Shared helpers

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
            // Individual tests assert on the resulting diagnostics.
        }
        return ctx
    }

    private func hasOptInAnnotation(
        on symbol: SymbolID,
        markerContaining keyword: String,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains {
            $0.annotationFQName.lowercased().contains(keyword.lowercased())
        }
    }

    private func className(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> String {
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            throw XCTSkip("Expected class type, got \(sema.types.kind(of: type))")
        }
        let symbol = try XCTUnwrap(sema.symbols.symbol(classType.classSymbol))
        return interner.resolve(symbol.name)
    }

    private func mapValueClassName(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> String {
        guard case let .classType(mapType) = sema.types.kind(of: type) else {
            throw XCTSkip("Expected Map class type, got \(sema.types.kind(of: type))")
        }
        let mapSymbol = try XCTUnwrap(sema.symbols.symbol(mapType.classSymbol))
        XCTAssertEqual(interner.resolve(mapSymbol.name), "Map")
        guard mapType.args.count >= 2,
              case let .out(valueType) = mapType.args[1]
        else {
            throw XCTSkip("Expected Map<String, V> value projection")
        }
        return try className(for: valueType, sema: sema, interner: interner)
    }

    // MARK: - Package hierarchy

    func testNativeRefPackageIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ref"].map { interner.intern($0) }
        XCTAssertNotNil(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.ref package to be registered"
        )
    }

    func testNativeRuntimePackageIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime"].map { interner.intern($0) }
        XCTAssertNotNil(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime package to be registered"
        )
    }

    func testNativeRuntimeApiMarkerIsRegisteredAsRequiresOptIn() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "NativeRuntimeApi"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime.NativeRuntimeApi to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.RequiresOptIn"
                    && $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
            },
            "NativeRuntimeApi should carry @RequiresOptIn(ERROR), got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments.contains("AnnotationTarget.FUNCTION")
                    && $0.arguments.contains("AnnotationTarget.PROPERTY")
                    && $0.arguments.contains("AnnotationTarget.TYPEALIAS")
            },
            "NativeRuntimeApi should carry the Kotlin/Native runtime target set, got \(annotations)"
        )
    }

    // MARK: - WeakReference<T>

    func testWeakReferenceClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.ref.WeakReference to be registered"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind, .class,
            "WeakReference should be a class"
        )
    }

    func testWeakReferenceHasTypeParameter() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
        let classSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: classFQName))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: classSymbol)
        XCTAssertEqual(typeParams.count, 1, "WeakReference should have exactly one type parameter")
    }

    func testWeakReferenceHasGetMember() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
        let getMemberFQName = classFQName + [interner.intern("get")]
        let members = sema.symbols.lookupAll(fqName: getMemberFQName)
        XCTAssertFalse(members.isEmpty, "WeakReference should have a get() member")

        let getMember = try XCTUnwrap(members.first)
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: getMember))
        XCTAssertEqual(
            signature.parameterTypes.count, 0,
            "WeakReference.get() should take no parameters"
        )
        // Return type should be nullable (T?)
        let returnKind = sema.types.kind(of: signature.returnType)
        if case let .typeParam(param) = returnKind {
            XCTAssertEqual(param.nullability, .nullable, "get() return type should be nullable T")
        } else {
            XCTFail("Expected return type to be a nullable type param, got \(returnKind)")
        }
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: getMember),
            "kk_weak_ref_get",
            "WeakReference.get() should lower to kk_weak_ref_get"
        )
    }

    func testWeakReferenceHasConstructor() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
        let ctorFQName = classFQName + [interner.intern("<init>")]
        let ctor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: ctorFQName).first,
            "WeakReference should have a constructor"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctor))
        XCTAssertEqual(signature.parameterTypes.count, 1)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: ctor),
            "kk_weak_ref_create",
            "WeakReference constructor should lower to kk_weak_ref_create"
        )
    }

    func testWeakReferenceHasClearMember() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
        let clearMemberFQName = classFQName + [interner.intern("clear")]
        let clearMember = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: clearMemberFQName).first,
            "WeakReference should have a clear() member"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: clearMember))
        XCTAssertEqual(signature.parameterTypes.count, 0)
        XCTAssertEqual(signature.returnType, sema.types.unitType)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: clearMember),
            "kk_weak_ref_clear",
            "WeakReference.clear() should lower to kk_weak_ref_clear"
        )
    }

    func testWeakReferenceIsTaggedExperimentalNativeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ref", "WeakReference"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "ExperimentalNativeApi", sema: sema),
            "WeakReference should carry @ExperimentalNativeApi annotation"
        )
    }

    // MARK: - createCleaner

    func testCreateCleanerFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ref", "createCleaner"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        XCTAssertFalse(symbols.isEmpty, "Expected kotlin.native.ref.createCleaner to be registered")
    }

    func testCreateCleanerHasTwoParameters() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ref", "createCleaner"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName).first)
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        XCTAssertEqual(
            signature.parameterTypes.count, 2,
            "createCleaner should accept (value, block)"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: sym),
            "kk_cleaner_create",
            "createCleaner should lower to kk_cleaner_create"
        )
    }

    func testCreateCleanerIsTaggedExperimentalNativeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ref", "createCleaner"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName).first)
        XCTAssertTrue(
            hasOptInAnnotation(on: sym, markerContaining: "ExperimentalNativeApi", sema: sema),
            "createCleaner should carry @ExperimentalNativeApi annotation"
        )
    }

    // MARK: - GC object

    func testGCObjectIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime.GC to be registered"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind, .object,
            "GC should be an object"
        )
    }

    func testGCHasCollectMember() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let collectFQName = objectFQName + [interner.intern("collect")]
        let members = sema.symbols.lookupAll(fqName: collectFQName)
        XCTAssertFalse(members.isEmpty, "GC should have a collect() member")

        let member = try XCTUnwrap(members.first)
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: member))
        XCTAssertEqual(sig.returnType, sema.types.unitType, "GC.collect() should return Unit")
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: member),
            "kk_gc_collect",
            "GC.collect() should lower to kk_gc_collect"
        )
    }

    func testGCHasScheduleMember() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let scheduleFQName = objectFQName + [interner.intern("schedule")]
        let members = sema.symbols.lookupAll(fqName: scheduleFQName)
        XCTAssertFalse(members.isEmpty, "GC should have a schedule() member")
        let member = try XCTUnwrap(members.first)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: member),
            "kk_gc_schedule",
            "GC.schedule() should lower to kk_gc_schedule"
        )
    }

    func testGCHasRuntimeTuningProperties() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let expected: [(name: String, type: TypeID, link: String)] = [
            ("targetHeapBytes", sema.types.longType, "kk_gc_target_heap_bytes"),
            ("targetHeapUtilization", sema.types.doubleType, "kk_gc_target_heap_utilization"),
            ("maxHeapBytes", sema.types.longType, "kk_gc_max_heap_bytes"),
        ]

        for property in expected {
            let propertyFQName = objectFQName + [interner.intern(property.name)]
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: propertyFQName),
                "GC should have \(property.name)"
            )
            XCTAssertEqual(sema.symbols.propertyType(for: symbol), property.type)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), property.link)
        }
    }

    func testGCIsTaggedNativeRuntimeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
            "GC should carry @NativeRuntimeApi annotation"
        )
    }

    // MARK: - RootSetStatistics class

    func testRootSetStatisticsClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "RootSetStatistics"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime.RootSetStatistics to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)
    }

    func testRootSetStatisticsHasConstructorAndProperties() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "runtime", "RootSetStatistics"].map { interner.intern($0) }
        let expectedProperties = [
            "threadLocalReferences",
            "stackReferences",
            "globalReferences",
            "stableReferences",
        ]

        for property in expectedProperties {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                "RootSetStatistics should expose \(property)"
            )
            XCTAssertEqual(sema.symbols.propertyType(for: symbol), sema.types.longType)
        }

        let ctor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first,
            "RootSetStatistics should expose its primary constructor"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctor))
        XCTAssertEqual(
            signature.parameterTypes,
            Array(repeating: sema.types.longType, count: expectedProperties.count)
        )
    }

    func testRootSetStatisticsIsTaggedNativeRuntimeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "RootSetStatistics"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
            "RootSetStatistics should carry @NativeRuntimeApi annotation"
        )
    }

    // MARK: - SweepStatistics class

    func testSweepStatisticsClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "SweepStatistics"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime.SweepStatistics to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)
    }

    func testSweepStatisticsHasConstructorAndProperties() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "runtime", "SweepStatistics"].map { interner.intern($0) }
        let expectedProperties = [
            "sweptCount",
            "keptCount",
        ]

        for property in expectedProperties {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                "SweepStatistics should expose \(property)"
            )
            XCTAssertEqual(sema.symbols.propertyType(for: symbol), sema.types.longType)
        }

        let ctor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first,
            "SweepStatistics should expose its primary constructor"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctor))
        XCTAssertEqual(
            signature.parameterTypes,
            Array(repeating: sema.types.longType, count: expectedProperties.count)
        )
    }

    func testSweepStatisticsIsTaggedNativeRuntimeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "SweepStatistics"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
            "SweepStatistics should carry @NativeRuntimeApi annotation"
        )
    }

    // MARK: - GCInfo class

    func testGCInfoClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime.GCInfo to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)
    }

    func testGCInfoConstructorMatchesKotlinNativeSurface() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
        let ctorFQName = classFQName + [interner.intern("<init>")]
        let ctor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: ctorFQName).first,
            "GCInfo should expose its primary constructor"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctor))
        XCTAssertEqual(signature.parameterTypes.count, 15)
        XCTAssertEqual(
            signature.parameterTypes[0],
            sema.types.longType,
            "GCInfo.epoch constructor parameter should be Long"
        )
        XCTAssertEqual(
            signature.parameterTypes[10],
            try XCTUnwrap(sema.symbols.propertyType(for: try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern("rootSet")])
            )))
        )
        XCTAssertEqual(
            signature.parameterTypes[12],
            try XCTUnwrap(sema.symbols.propertyType(for: try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern("sweepStatistics")])
            )))
        )
    }

    func testGCInfoHasTimingProperties() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
        let longProperties = [
            "epoch",
            "startTimeNs",
            "endTimeNs",
            "firstPauseRequestTimeNs",
            "firstPauseStartTimeNs",
            "firstPauseEndTimeNs",
        ]
        for property in longProperties {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                "GCInfo should expose \(property)"
            )
            XCTAssertEqual(sema.symbols.propertyType(for: symbol), sema.types.longType)
        }

        let nullableLongProperties = [
            "secondPauseRequestTimeNs",
            "secondPauseStartTimeNs",
            "secondPauseEndTimeNs",
            "postGcCleanupTimeNs",
        ]
        for property in nullableLongProperties {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern(property)]),
                "GCInfo should expose \(property)"
            )
            let type = try XCTUnwrap(sema.symbols.propertyType(for: symbol))
            XCTAssertEqual(sema.types.nullability(of: type), .nullable)
            XCTAssertEqual(sema.types.makeNonNullable(type), sema.types.longType)
        }
    }

    func testGCInfoHasSummaryProperties() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }

        let rootSetSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName + [interner.intern("rootSet")])
        )
        let rootSetType = try XCTUnwrap(sema.symbols.propertyType(for: rootSetSymbol))
        XCTAssertEqual(
            try className(for: rootSetType, sema: sema, interner: interner),
            "RootSetStatistics"
        )

        let markedCountSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName + [interner.intern("markedCount")])
        )
        XCTAssertEqual(sema.symbols.propertyType(for: markedCountSymbol), sema.types.longType)

        let sweepStatisticsSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName + [interner.intern("sweepStatistics")])
        )
        XCTAssertEqual(
            try mapValueClassName(
                for: try XCTUnwrap(sema.symbols.propertyType(for: sweepStatisticsSymbol)),
                sema: sema,
                interner: interner
            ),
            "SweepStatistics"
        )

        for property in ["memoryUsageBefore", "memoryUsageAfter"] {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: classFQName + [interner.intern(property)])
            )
            XCTAssertEqual(
                try mapValueClassName(
                    for: try XCTUnwrap(sema.symbols.propertyType(for: symbol)),
                    sema: sema,
                    interner: interner
                ),
                "MemoryUsage"
            )
        }
    }

    func testMemoryUsageSurfaceForGCInfoIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let classFQName = ["kotlin", "native", "runtime", "MemoryUsage"].map { interner.intern($0) }
        let classSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: classFQName))
        XCTAssertEqual(sema.symbols.symbol(classSymbol)?.kind, .class)
        XCTAssertTrue(
            hasOptInAnnotation(on: classSymbol, markerContaining: "NativeRuntimeApi", sema: sema),
            "MemoryUsage should carry @NativeRuntimeApi annotation"
        )

        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName + [interner.intern("totalObjectsSizeBytes")])
        )
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.longType)

        let ctor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctor))
        XCTAssertEqual(signature.parameterTypes, [sema.types.longType])
    }

    func testGCInfoIsTaggedNativeRuntimeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "GCInfo"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
            "GCInfo should carry @NativeRuntimeApi annotation"
        )
    }

    // MARK: - Debugging object

    func testDebuggingObjectIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.native.runtime.Debugging to be registered"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind, .object,
            "Debugging should be an object"
        )
    }

    func testDebuggingHasIsThreadStateRunnableProperty() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let propFQName = objectFQName + [interner.intern("isThreadStateRunnable")]
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: propFQName),
            "Debugging should expose isThreadStateRunnable property"
        )
        XCTAssertEqual(
            sema.symbols.propertyType(for: sym), sema.types.booleanType,
            "isThreadStateRunnable should be Boolean"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: sym),
            "kk_debugging_is_thread_state_runnable"
        )
    }

    func testDebuggingHasTrackingProperties() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let expected: [(name: String, link: String)] = [
            ("gcSuspendCount", "kk_debugging_gc_suspend_count"),
            ("threadCount", "kk_debugging_thread_count"),
            ("globalObjectCount", "kk_debugging_global_object_count"),
        ]

        for property in expected {
            let propFQName = objectFQName + [interner.intern(property.name)]
            let sym = try XCTUnwrap(
                sema.symbols.lookup(fqName: propFQName),
                "Debugging should expose \(property.name) property"
            )
            XCTAssertEqual(
                sema.symbols.propertyType(for: sym), sema.types.intType,
                "\(property.name) should be Int"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: sym), property.link)
        }
    }

    func testDebuggingIsTaggedNativeRuntimeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "NativeRuntimeApi", sema: sema),
            "Debugging should carry @NativeRuntimeApi annotation"
        )
    }

    // MARK: - Opt-in diagnostic integration

    func testUsingWeakReferenceWithoutOptInProducesDiagnostic() {
        let source = """
        import kotlin.native.ref.WeakReference

        fun probe(s: String): WeakReference<String> {
            return WeakReference(s)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        XCTAssertFalse(
            optInDiagnostics.isEmpty,
            "Expected opt-in diagnostic for WeakReference usage without @OptIn"
        )
    }

    func testUsingWeakReferenceWithOptInSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.ref.WeakReference

        fun probe(s: String): WeakReference<String> {
            return WeakReference(s)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        XCTAssertTrue(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when @OptIn(ExperimentalNativeApi::class) is present"
        )
    }

    func testUsingGCWithoutNativeRuntimeApiOptInProducesDiagnostic() {
        let source = """
        import kotlin.native.runtime.GC

        fun probe() {
            GC.collect()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        XCTAssertFalse(
            optInDiagnostics.isEmpty,
            "Expected opt-in diagnostic for GC usage without @OptIn(NativeRuntimeApi::class)"
        )
    }

    func testUsingGCWithNativeRuntimeApiOptInSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
        import kotlin.native.runtime.GC

        fun probe() {
            GC.collect()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        XCTAssertTrue(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when @OptIn(NativeRuntimeApi::class) is present"
        )
    }
}
