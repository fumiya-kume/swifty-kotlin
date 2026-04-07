// SKIP-DIFF: kotlin.native.* and kotlinx.cinterop.* APIs are only available on Kotlin/Native targets.
import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.CName
import kotlin.native.Platform
import kotlin.native.CpuArchitecture
import kotlin.native.OsFamily
import kotlin.native.ref.Pinned
import kotlin.native.concurrent.Worker
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.alloc

// ── @CName ──────────────────────────────────────────────────────────────────

@ExperimentalNativeApi
@CName(externName = "native_add", shortName = "native_add")
fun nativeAdd(a: Int, b: Int): Int = a + b

// ── CPointer / COpaquePointer ────────────────────────────────────────────────

@OptIn(ExperimentalForeignApi::class)
fun demonstrateCPointers() {
    val ptr: CPointer<IntVar>? = null
    val opaque: COpaquePointer? = null
    println("cpointer_null=${ptr == null}")
    println("copaque_null=${opaque == null}")
}

// ── memScoped { } ────────────────────────────────────────────────────────────

@OptIn(ExperimentalForeignApi::class)
fun demonstrateMemScoped() {
    memScoped {
        val v = alloc<IntVar>()
        v.value = 42
        println("memScoped_value=${v.value}")
    }
}

// ── freeze / isFrozen (legacy Kotlin/Native immutability) ────────────────────

@ExperimentalNativeApi
fun demonstrateFreeze() {
    val list = mutableListOf(1, 2, 3)
    // freeze() marks an object as immutable in Kotlin/Native legacy MM
    list.freeze()
    println("list_frozen=${list.isFrozen}")
}

// ── Worker API ────────────────────────────────────────────────────────────────

fun demonstrateWorker() {
    val worker = Worker.start(name = "demo-worker")
    val future = worker.execute(TransferMode.SAFE, { 21 }) { input -> input * 2 }
    val result = future.result
    println("worker_result=${result}")
    worker.requestTermination(processScheduled = false).result
}

// ── Platform.cpuArchitecture / Platform.osFamily ─────────────────────────────

fun demonstratePlatform() {
    val os = Platform.osFamily
    val arch = Platform.cpuArchitecture
    println("os_known=${os != OsFamily.UNKNOWN}")
    println("arch_known=${arch != CpuArchitecture.UNKNOWN}")
    println("cpus_positive=${Platform.getAvailableProcessors() > 0}")
}

fun main() {
    demonstrateCPointers()
    demonstrateMemScoped()
    @OptIn(ExperimentalNativeApi::class)
    demonstrateFreeze()
    demonstratePlatform()
    // Worker demo is omitted from main() as it requires Kotlin/Native runtime
    println("native_api_ok=true")
}
