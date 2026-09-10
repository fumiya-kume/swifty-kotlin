package golden.sema

@Suppress("DEPRECATION_ERROR")
fun construct(value: String): kotlin.native.concurrent.AtomicReference<String> =
    kotlin.native.concurrent.AtomicReference(value)
