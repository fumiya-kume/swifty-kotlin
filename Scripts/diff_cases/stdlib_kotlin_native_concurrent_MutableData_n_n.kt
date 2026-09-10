// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.MutableData

fun main() {
    val defaultData = MutableData()
    val explicitData = MutableData(4)
    println(defaultData === explicitData)
}
