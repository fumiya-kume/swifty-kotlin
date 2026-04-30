/// STDLIB-NATIVE-REF-002: Sema-level tests for `kotlin.native.ref` and
/// `kotlin.native.runtime` exposure.
///
/// Verifies:
/// 1. Name resolution — all symbols are registered and look-uppable.
/// 2. Signature visibility — member signatures have the expected shape.
/// 3. Experimental opt-in requirement — symbols carry the
///    `@ExperimentalNativeApi` annotation so opt-in diagnostics fire.

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
    }

    func testGCHasScheduleMember() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let scheduleFQName = objectFQName + [interner.intern("schedule")]
        let members = sema.symbols.lookupAll(fqName: scheduleFQName)
        XCTAssertFalse(members.isEmpty, "GC should have a schedule() member")
    }

    func testGCIsTaggedExperimentalNativeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "GC"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "ExperimentalNativeApi", sema: sema),
            "GC should carry @ExperimentalNativeApi annotation"
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
    }

    func testDebuggingHasGcSuspendCountProperty() throws {
        let (sema, interner) = try makeSema()
        let objectFQName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let propFQName = objectFQName + [interner.intern("gcSuspendCount")]
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: propFQName),
            "Debugging should expose gcSuspendCount property"
        )
        XCTAssertEqual(
            sema.symbols.propertyType(for: sym), sema.types.intType,
            "gcSuspendCount should be Int"
        )
    }

    func testDebuggingIsTaggedExperimentalNativeApi() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "runtime", "Debugging"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        XCTAssertTrue(
            hasOptInAnnotation(on: symbol, markerContaining: "ExperimentalNativeApi", sema: sema),
            "Debugging should carry @ExperimentalNativeApi annotation"
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
}
