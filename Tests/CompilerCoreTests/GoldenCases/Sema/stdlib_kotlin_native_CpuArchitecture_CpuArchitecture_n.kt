@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.CpuArchitecture

fun cpuArchitectureEntries(): kotlin.enums.EnumEntries<CpuArchitecture> = CpuArchitecture.entries
fun cpuArchitectureBitness(): Int = CpuArchitecture.ARM64.bitness
fun cpuArchitectureValueOf(): CpuArchitecture = CpuArchitecture.valueOf("WASM32")
fun cpuArchitectureValues(): Array<CpuArchitecture> = CpuArchitecture.values()
