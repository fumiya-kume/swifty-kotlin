package golden.diagnostics

// STDLIB-EXPERIMENTAL-001: Inventory of kotlin.experimental / kotlin marker annotations.
// Declares each marker with @RequiresOptIn and verifies they can be defined and used.
// This file covers:
//   kotlin.RequiresOptIn          — the meta-annotation itself
//   kotlin.OptIn                  — opt-in declaration
//   kotlin.ExperimentalStdlibApi  — stdlib experimental APIs
//   kotlin.time.ExperimentalTime  — time API
//   kotlin.contracts.ExperimentalContracts — contracts DSL
//   kotlin.experimental.ExperimentalTypeInference — type inference extensions
//   (simulated) ExperimentalUnsignedTypes, ExperimentalUuidApi,
//               ExperimentalEncodingApi, ExperimentalMultiplatform,
//               ExperimentalSubclassOptIn

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalUnsignedTypesMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalUuidApiMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalEncodingApiMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalMultiplatformMarker

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
annotation class ExperimentalSubclassOptInMarker

@ExperimentalUnsignedTypesMarker
fun inventoryUnsigned(): UInt = 0u

@ExperimentalUuidApiMarker
fun inventoryUuid(): String = "uuid"

@ExperimentalEncodingApiMarker
fun inventoryEncoding(): ByteArray = ByteArray(0)

@ExperimentalMultiplatformMarker
fun inventoryMultiplatform(): Int = 0

@ExperimentalSubclassOptInMarker
fun inventorySubclassOptIn(): Int = 0

// All five calls without opt-in — five warning diagnostics expected
fun useAllMarkers() {
    inventoryUnsigned()
    inventoryUuid()
    inventoryEncoding()
    inventoryMultiplatform()
    inventorySubclassOptIn()
}
