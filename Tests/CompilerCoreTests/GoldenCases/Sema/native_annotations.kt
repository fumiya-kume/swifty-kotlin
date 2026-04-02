package golden.sema

import kotlin.experimental.ExperimentalNativeApi
import kotlin.experimental.ExperimentalObjCEnum
import kotlin.experimental.ExperimentalObjCName
import kotlin.experimental.ExperimentalObjCRefinement
import kotlin.native.CName
import kotlin.native.ObjCName
import kotlin.native.RefinesInSwift
import kotlin.native.ShouldRefineInSwift
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CValuesRef
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.IntVar

@ExperimentalObjCRefinement
@Target(AnnotationTarget.FUNCTION)
annotation class SwiftRefined

@ExperimentalObjCEnum
@Target(AnnotationTarget.ANNOTATION_CLASS)
annotation class NativeEnumBridge

@NativeEnumBridge
@Target(AnnotationTarget.CLASS)
annotation class ExportEnumToObjC

@ObjCName(name = "NativeGreeter", swiftName = "NativeGreeter", exact = true)
class NativeGreeter {
    @ShouldRefineInSwift
    @SwiftRefined
    fun greet(@ObjCName(name = "person", swiftName = "person") person: String): String = person
}

@RefinesInSwift
annotation class SwiftFacade

@ExportEnumToObjC
enum class NativeStatus {
    OK,
    FAIL,
}

@ExperimentalNativeApi
@CName(externName = "native_sum", shortName = "native_sum")
fun nativeSum(a: Int, b: Int): Int = a + b

@ExperimentalForeignApi
fun takesPointer(
    ptr: CPointer<IntVar>?,
    opaque: COpaquePointer?,
    ints: CValuesRef<IntVar>?,
): CPointer<IntVar>? = ptr
