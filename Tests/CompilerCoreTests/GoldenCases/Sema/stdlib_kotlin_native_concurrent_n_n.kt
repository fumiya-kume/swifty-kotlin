@file:Suppress("DEPRECATION_ERROR")
@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.concurrent.*
import kotlin.native.internal.NativePtr
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.CPointer

fun preserveAtomicInt(value: kotlin.native.concurrent.AtomicInt): kotlin.native.concurrent.AtomicInt = value
fun preserveAtomicLong(value: kotlin.native.concurrent.AtomicLong): kotlin.native.concurrent.AtomicLong = value
fun preserveAtomicNativePtr(value: kotlin.native.concurrent.AtomicNativePtr): kotlin.native.concurrent.AtomicNativePtr = value
fun preserveAtomicReference(value: kotlin.native.concurrent.AtomicReference<String?>): kotlin.native.concurrent.AtomicReference<String?> = value
fun preserveContinuation0(value: Continuation0): Continuation0 = value
fun preserveContinuation1(value: Continuation1<Int>): Continuation1<Int> = value
fun preserveContinuation2(value: Continuation2<Int, String>): Continuation2<Int, String> = value
fun preserveDetachedObjectGraph(value: DetachedObjectGraph<String>): DetachedObjectGraph<String> = value
fun preserveFreezableAtomicReference(value: FreezableAtomicReference<String?>): FreezableAtomicReference<String?> = value
fun preserveFreezingException(value: FreezingException): FreezingException = value
fun preserveFuture(value: Future<Int>): Future<Int> = value
fun preserveFutureState(value: FutureState): FutureState = value
fun preserveInvalidMutabilityException(value: InvalidMutabilityException): InvalidMutabilityException = value
fun preserveMutableData(value: MutableData): MutableData = value
fun preserveObsoleteWorkersApi(value: ObsoleteWorkersApi): ObsoleteWorkersApi = value
fun preserveSharedImmutable(value: SharedImmutable): SharedImmutable = value
fun preserveThreadLocal(value: kotlin.native.concurrent.ThreadLocal): kotlin.native.concurrent.ThreadLocal = value
fun preserveTransferMode(value: TransferMode): TransferMode = value
fun preserveWorker(value: Worker): Worker = value
fun preserveWorkerBoundReference(value: WorkerBoundReference<String>): WorkerBoundReference<String> = value

fun atomicLazyValue(initializer: () -> Int): Lazy<Int> = atomicLazy(initializer)
fun attachGraph(stable: NativePtr): Any? = attachObjectGraphInternal(stable)
fun consume(id: Int): Any? = consumeFuture(id)
fun detachGraph(mode: Int, producer: () -> Any?): NativePtr =
    detachObjectGraphInternal(mode, producer)
fun execute(worker: Worker, mode: TransferMode, producer: () -> Any?, job: CPointer<CFunction<*>>): Future<Any?> =
    executeImpl(worker, mode, producer, job)
fun freezeValue(value: String): String = value.freeze()
fun waitForFutures(futures: Collection<Future<Int>>): Set<Future<Int>> =
    waitForMultipleFutures(futures, 0)
fun waitForWorker(worker: Worker): Unit = waitWorkerTermination(worker)
fun useWorker(): Int = withWorker(null, true) { 42 }
