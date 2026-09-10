@file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_future_consume")
@PublishedApi
internal external fun <T> __kkFutureConsume(id: Int): T

@KsSymbolName("kk_future_invoke")
@PublishedApi
internal external fun <T, R> __kkFutureInvoke(code: (T) -> R, value: T): R

@KsSymbolName("kk_future_getState")
private external fun __kkFutureGetState(id: Int): Int

private fun sameFuture(id: Int, other: Any?): Boolean =
    other is Future<*> && id == other.id

/**
 * Class representing abstract computation, whose result may become available in the future.
 */
@Suppress("NON_PUBLIC_PRIMARY_CONSTRUCTOR_OF_INLINE_CLASS")
@ObsoleteWorkersApi
public value class Future<T> @PublishedApi internal constructor(public val id: Int) {
    @KsSymbolName("kk_future_consume")
    @PublishedApi
    internal external fun consumeValue(): T

    /** Blocks execution until the future is ready and consumes its result. */
    public inline fun <R> consume(code: (T) -> R): R = when (state) {
        FutureState.SCHEDULED, FutureState.COMPUTED -> {
            val value = __kkFutureConsume<T>(id)
            __kkFutureInvoke(code, value)
        }
        FutureState.INVALID ->
            throw IllegalStateException("Future is in an invalid state")
        FutureState.CANCELLED -> {
            val ignored = __kkFutureConsume<Any?>(id)
            throw IllegalStateException("Future is cancelled")
        }
        FutureState.THROWN -> {
            val ignored = __kkFutureConsume<Any?>(id)
            throw IllegalStateException("Job has thrown an exception")
        }
    }

    /** Blocks execution until the future is ready. */
    public val result: T
        get() = consumeValue()

    /** Returns the current state of this future. */
    public val state: FutureState
        get() = FutureState.values()[__kkFutureGetState(id)]

    override fun equals(other: Any?): Boolean = sameFuture(id, other)

    override fun hashCode(): Int = id

    override fun toString(): String = "future $id"
}
