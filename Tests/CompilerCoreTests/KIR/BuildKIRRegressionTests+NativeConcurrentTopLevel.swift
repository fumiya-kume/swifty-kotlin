#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testNativeConcurrentTopLevelFunctionsRetainSourceAndBridgeBoundaries() throws {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

        import kotlin.native.concurrent.Future
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker
        import kotlin.native.concurrent.atomicLazy
        import kotlin.native.concurrent.attachObjectGraphInternal
        import kotlin.native.concurrent.consumeFuture
        import kotlin.native.concurrent.detachObjectGraphInternal
        import kotlin.native.concurrent.executeImpl
        import kotlin.native.concurrent.freeze
        import kotlin.native.concurrent.waitForMultipleFutures
        import kotlin.native.concurrent.waitWorkerTermination
        import kotlin.native.concurrent.withWorker
        import kotlin.native.internal.NativePtr
        import kotlinx.cinterop.CFunction
        import kotlinx.cinterop.CPointer

        fun nativeConcurrentProbe(
            futures: Collection<Future<Int>>,
            worker: Worker,
            stable: NativePtr,
            job: CPointer<CFunction<*>>
        ): Int {
            val lazyValue = atomicLazy { 42 }
            val frozen = lazyValue.value.freeze()
            attachObjectGraphInternal(stable)
            consumeFuture(0)
            detachObjectGraphInternal(0) { frozen }
            executeImpl(worker, TransferMode.SAFE, { frozen }, job)
            waitForMultipleFutures(futures, 0)
            waitWorkerTermination(worker)
            return withWorker(null, true) { frozen }
        }
        """

        try withTemporaryFile(contents: source) { path in
            // Executable KIR includes bundled stdlib bodies; kirDump consumer
            // modules intentionally omit them in favor of the stdlib artifact.
            let context = makeCompilationContext(inputs: [path], emit: .executable)
            try runToKIR(context)

            let sema = try #require(context.sema)
            let module = try #require(context.kir)
            let consumerBody = try findKIRFunctionBody(
                named: "nativeConcurrentProbe",
                in: module,
                interner: context.interner
            )
            let consumerCallees = Set(extractCallees(from: consumerBody, interner: context.interner))
            for callee in [
                "atomicLazy", "freeze", "waitForMultipleFutures",
                "waitWorkerTermination", "withWorker",
            ] {
                #expect(
                    consumerCallees.contains(callee),
                    "Expected consumer KIR to retain source call to \(callee); got \(consumerCallees)"
                )
            }

            let bridgeExpectations: [String: Set<String>] = [
                "attachObjectGraphInternal": ["__kk_native_concurrent_attach_object_graph"],
                "consumeFuture": ["__kk_native_concurrent_consume_future"],
                "detachObjectGraphInternal": ["__kk_native_concurrent_detach_object_graph"],
                "executeImpl": ["__kk_native_concurrent_execute_impl"],
                "waitForMultipleFutures": ["__kk_native_concurrent_wait_for_multiple_futures"],
                "waitWorkerTermination": ["__kk_native_concurrent_wait_worker_termination"],
                "withWorker": [
                    "__kk_native_concurrent_start_worker",
                    "__kk_native_concurrent_terminate_worker",
                ],
            ]
            let package = ["kotlin", "native", "concurrent"]
            let functions = findAllKIRFunctions(in: module)

            for (name, expectedBridges) in bridgeExpectations {
                let symbols = sema.symbols.lookupAll(
                    fqName: (package + [name]).map(context.interner.intern)
                ).filter { symbol in
                    guard let fileID = sema.symbols.sourceFileID(for: symbol) else {
                        return false
                    }
                    return context.sourceManager.path(of: fileID)
                        == "__bundled_kotlin/native/concurrent/Stdlib.kt"
                }
                let symbol = try #require(symbols.first, "Expected source symbol for \(name)")
                let function = try #require(
                    functions.first { $0.symbol == symbol },
                    "Expected KIR body for \(name)"
                )
                let callees = Set(extractCallees(from: function.body, interner: context.interner))
                #expect(
                    expectedBridges.isSubset(of: callees),
                    "Expected \(name) to route through \(expectedBridges); got \(callees)"
                )
            }
        }
    }
}
#endif
