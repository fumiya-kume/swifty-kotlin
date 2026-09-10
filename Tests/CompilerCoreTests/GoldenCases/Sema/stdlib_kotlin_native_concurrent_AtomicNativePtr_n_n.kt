package golden.sema

@Suppress("DEPRECATION_ERROR")
fun construct(value: kotlinx.cinterop.NativePtr): kotlin.native.concurrent.AtomicNativePtr =
    kotlin.native.concurrent.AtomicNativePtr(value)
