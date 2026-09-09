package golden.sema

@Suppress("DEPRECATION_ERROR")
fun constructDefault(): kotlin.native.concurrent.AtomicLong =
    kotlin.native.concurrent.AtomicLong()

@Suppress("DEPRECATION_ERROR")
fun constructExplicit(value: Long): kotlin.native.concurrent.AtomicLong =
    kotlin.native.concurrent.AtomicLong(value)
