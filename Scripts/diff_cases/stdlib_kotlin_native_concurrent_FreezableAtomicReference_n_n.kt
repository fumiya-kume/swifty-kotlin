// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.FreezableAtomicReference

fun construct(value: Int): FreezableAtomicReference<Int> =
    FreezableAtomicReference(value)

fun main() {}
