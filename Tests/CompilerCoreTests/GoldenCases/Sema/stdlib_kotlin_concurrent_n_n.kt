@file:OptIn(kotlin.ExperimentalStdlibApi::class, kotlinx.cinterop.ExperimentalForeignApi::class)

package golden.sema

import kotlin.concurrent.AtomicArray
import kotlin.concurrent.AtomicInt
import kotlin.concurrent.AtomicIntArray
import kotlin.concurrent.AtomicLong
import kotlin.concurrent.AtomicLongArray
import kotlin.concurrent.AtomicNativePtr
import kotlin.concurrent.AtomicReference

fun atomicIntType(): AtomicInt? = null
fun atomicLongType(): AtomicLong? = null
fun atomicReferenceType(value: AtomicReference<String>): AtomicReference<String> = value
fun atomicArrayType(value: AtomicArray<String?>): AtomicArray<String?> = value
fun atomicNativePtrType(): AtomicNativePtr? = null

fun atomicIntArrayFactory(): AtomicIntArray = AtomicIntArray(2) { it }
fun atomicLongArrayFactory(): AtomicLongArray = AtomicLongArray(2) { it.toLong() }
fun atomicArrayFactory(): AtomicArray<String> = AtomicArray(2) { it.toString() }
