package golden.sema

import kotlin.coroutines.cancellation.CancellationException

fun noArg(): CancellationException = CancellationException()

fun message(message: String?): CancellationException = CancellationException(message)

fun cause(cause: Throwable?): CancellationException = CancellationException(cause)

fun messageAndCause(message: String?, cause: Throwable?): CancellationException =
    CancellationException(message, cause)
