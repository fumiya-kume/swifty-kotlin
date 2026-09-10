// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are unavailable in the JVM kotlinc reference environment.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.CpuArchitecture

fun main() {
    println(CpuArchitecture.UNKNOWN.bitness)
    println(CpuArchitecture.ARM64.bitness)
    println(CpuArchitecture.entries.size)
    println(CpuArchitecture.values().size)
    println(CpuArchitecture.valueOf("WASM32"))
}
