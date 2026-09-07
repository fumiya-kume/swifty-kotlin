package kotlin.reflect

// KSP-1337: Keep KVariance source-backed so the generic enum pipeline owns
// entries, valueOf, and values using the Kotlin declaration order.
public enum class KVariance {
    INVARIANT,
    IN,
    OUT
}
