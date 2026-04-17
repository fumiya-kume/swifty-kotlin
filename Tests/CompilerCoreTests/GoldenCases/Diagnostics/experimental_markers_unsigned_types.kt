package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: ExperimentalUnsignedTypes inventory marker.
// This marker gates UInt, ULong, UByte, UShort in the Kotlin stdlib.
// Here we simulate the pattern: a user-defined marker gates unsigned-type-returning APIs.

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalUnsignedTypes

@ExperimentalUnsignedTypes
fun uintApi(): UInt = 0u

@ExperimentalUnsignedTypes
fun ulongApi(): ULong = 0uL

@ExperimentalUnsignedTypes
fun ubyteApi(): UByte = 0u

@ExperimentalUnsignedTypes
fun ushortApi(): UShort = 0u

// Call without opt-in — four warning diagnostics expected (one per call)
fun useUnsignedApis() {
    uintApi()
    ulongApi()
    ubyteApi()
    ushortApi()
}
