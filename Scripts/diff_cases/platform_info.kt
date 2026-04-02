import kotlin.native.CpuArchitecture
import kotlin.native.OsFamily
import kotlin.native.Platform

private fun osFamilyLabel(): String {
    val family = Platform.osFamily
    return if (family == OsFamily.MACOSX) "MACOSX"
    else if (family == OsFamily.IOS) "IOS"
    else if (family == OsFamily.TVOS) "TVOS"
    else if (family == OsFamily.WATCHOS) "WATCHOS"
    else if (family == OsFamily.LINUX) "LINUX"
    else if (family == OsFamily.WINDOWS) "WINDOWS"
    else if (family == OsFamily.ANDROID) "ANDROID"
    else if (family == OsFamily.WASM) "WASM"
    else "UNKNOWN"
}

private fun cpuArchitectureLabel(): String {
    val arch = Platform.cpuArchitecture
    return if (arch == CpuArchitecture.X64) "X64"
    else if (arch == CpuArchitecture.X86) "X86"
    else if (arch == CpuArchitecture.ARM64) "ARM64"
    else if (arch == CpuArchitecture.ARM32) "ARM32"
    else if (arch == CpuArchitecture.MIPS32) "MIPS32"
    else if (arch == CpuArchitecture.MIPSEL32) "MIPSEL32"
    else if (arch == CpuArchitecture.WASM32) "WASM32"
    else "UNKNOWN"
}

fun main() {
    println("unaligned=${Platform.canAccessUnaligned}")
    println("little=${Platform.isLittleEndian}")
    println("os=${osFamilyLabel()}")
    println("arch=${cpuArchitectureLabel()}")
    println("cpus=${Platform.getAvailableProcessors()}")
}
