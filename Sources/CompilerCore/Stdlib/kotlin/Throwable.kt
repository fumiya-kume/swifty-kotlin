package kotlin

import kotlin.internal.KsSymbolName

/**
 * The base class for all errors and exceptions. Only instances of this class
 * can be thrown or caught.
 *
 * The actual storage is allocated by the runtime as a boxed exception object;
 * the Kotlin-level class declares the type, its public constructor surface and
 * its members. Members are expressed in Kotlin and reach the boxed storage
 * through the small `__kk_throwable_*` accessor bridges below. The mutating /
 * suppressed-list members remain extensions with static dispatch, while the
 * virtual members route through the runtime bridge for boxed Throwable values.
 */
public open class Throwable {
    @KsSymbolName("__kk_throwable_new")
    public constructor()

    @KsSymbolName("__kk_throwable_new")
    public constructor(message: String?)

    @KsSymbolName("__kk_throwable_new_cause")
    public constructor(cause: Throwable?)

    @KsSymbolName("__kk_throwable_new_with_cause")
    public constructor(message: String?, cause: Throwable?)

    public val message: String?
        get() = __kkThrowableMessage(this)

    public val cause: Throwable?
        get() = __kkThrowableCause(this)

    public fun getStackTrace(): Array<String> = __kkThrowableRawStackFrames(this)

    public override fun toString(): String = __kkThrowableToString(this)
}

public fun Throwable.initCause(cause: Throwable?): Throwable {
    __kkThrowableSetCause(this, cause)
    return this
}

public fun Throwable.addSuppressed(exception: Throwable) {
    if (exception !== this) {
        __kkThrowableAppendSuppressed(this, exception)
    }
}

public fun Throwable.getSuppressed(): Array<Throwable> = __kkThrowableSuppressedRaw(this)

public val Throwable.suppressedExceptions: List<Throwable>
    get() = __kkThrowableSuppressedRaw(this).toList()

public fun Throwable.stackTraceToString(): String {
    val lines = mutableListOf<String>()
    collectThrowableTraceLines(this, lines, null)
    return lines.joinToString("\n")
}

private fun collectThrowableTraceLines(
    throwable: Throwable,
    lines: MutableList<String>,
    prefix: String?
) {
    val frames = __kkThrowableRawStackFrames(throwable)
    for (i in 0 until frames.size) {
        val line = if (prefix != null && i == 0) prefix + frames[i] else frames[i]
        lines.add(line)
    }

    val suppressed = throwable.getSuppressed()
    for (i in 0 until suppressed.size) {
        collectThrowableTraceLines(suppressed[i], lines, "Suppressed: ")
    }

    val cause = throwable.cause
    if (cause != null) {
        collectThrowableTraceLines(cause, lines, "Caused by: ")
    }
}

public fun Throwable.printStackTrace() {
    __kkPrintStderr(this.stackTraceToString() + "\n")
}

@KsSymbolName("__kk_throwable_message")
internal external fun __kkThrowableMessage(throwable: Throwable): String?

@KsSymbolName("__kk_throwable_setMessage")
internal external fun __kkThrowableSetMessage(throwable: Throwable, message: String?)

@KsSymbolName("__kk_throwable_cause")
internal external fun __kkThrowableCause(throwable: Throwable): Throwable?

@KsSymbolName("__kk_throwable_setCause")
internal external fun __kkThrowableSetCause(throwable: Throwable, cause: Throwable?)

@KsSymbolName("__kk_throwable_appendSuppressed")
internal external fun __kkThrowableAppendSuppressed(throwable: Throwable, exception: Throwable)

@KsSymbolName("__kk_throwable_suppressedRaw")
internal external fun __kkThrowableSuppressedRaw(throwable: Throwable): Array<Throwable>

@KsSymbolName("__kk_throwable_rawStackFrames")
internal external fun __kkThrowableRawStackFrames(throwable: Throwable): Array<String>

@KsSymbolName("__kk_throwable_toString")
internal external fun __kkThrowableToString(throwable: Throwable): String

@KsSymbolName("__kk_printStderr")
internal external fun __kkPrintStderr(message: String)
