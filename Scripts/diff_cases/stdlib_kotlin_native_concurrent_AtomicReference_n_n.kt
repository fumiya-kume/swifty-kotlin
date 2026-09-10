// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.AtomicReference

fun main() {
    val reference = AtomicReference("initial")
    println(reference != null)
}
