package kotlin.native

// KSP-1198: Keep the Kotlin/Native enum declaration source-backed so bitness
// and the compiler-generated enum APIs follow the Kotlin 2.3.10 contract.
@kotlin.experimental.ExperimentalNativeApi
public enum class CpuArchitecture(public val bitness: Int) {
    UNKNOWN(-1),
    ARM32(32),
    ARM64(64),
    X86(32),
    X64(64),
    MIPS32(32),
    MIPSEL32(32),
    WASM32(32)
}
