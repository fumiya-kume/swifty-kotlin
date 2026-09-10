package kotlin.native.concurrent

// KSP-1226: Keep the legacy native AtomicReference constructor source-backed.
// Its value and atomic member operations are owned by KSP-1227.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class AtomicReference<T>(value: T)
