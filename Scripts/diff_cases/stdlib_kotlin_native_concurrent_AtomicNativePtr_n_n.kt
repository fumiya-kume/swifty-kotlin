// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlinx.cinterop.NativePtr
import kotlin.native.concurrent.AtomicNativePtr

fun construct(value: NativePtr): AtomicNativePtr = AtomicNativePtr(value)

fun main() {}
