package kotlin.reflect

import kotlin.internal.KsSymbolName

// KSP-1334: the constructor allocates the runtime reflection box and keeps
// Kotlin's nullable-pair validation in the native runtime bridge.
public class KTypeProjection {
    @KsSymbolName("__kk_ktypeprojection_create_checked")
    public constructor(variance: KVariance?, type: KType?)

    @KsSymbolName("__kk_ktypeprojection_get_variance")
    private external fun varianceComponent(): KVariance?

    @KsSymbolName("__kk_ktypeprojection_get_type")
    private external fun typeComponent(): KType?

    public val variance: KVariance?
        get() = varianceComponent()

    public val type: KType?
        get() = typeComponent()

    public operator fun component1(): KVariance? = variance

    public operator fun component2(): KType? = type

    public fun copy(
        variance: KVariance? = this.variance,
        type: KType? = this.type
    ): KTypeProjection = KTypeProjection(variance, type)

    override fun equals(other: Any?): Boolean {
        val o = other as? KTypeProjection ?: return false
        return variance == o.variance && type == o.type
    }

    override fun hashCode(): Int = 31 * (variance?.hashCode() ?: 0) + (type?.hashCode() ?: 0)

    override fun toString(): String {
        val variance = this.variance
        return when {
            variance == null -> "*"
            variance == KVariance.IN -> "in $type"
            variance == KVariance.OUT -> "out $type"
            else -> "$type"
        }
    }

    public companion object {}
}
