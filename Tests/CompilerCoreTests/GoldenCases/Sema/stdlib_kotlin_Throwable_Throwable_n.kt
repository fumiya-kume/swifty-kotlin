package golden.sema

private class NamedThrowable(message: String?) : Throwable(message)

private class NoArgThrowable : Throwable()

private class MessageCauseThrowable(message: String?, cause: Throwable?) : Throwable(message, cause)

private class OverridingThrowable : Throwable("base") {
    override fun toString(): String = "override"
}

fun throwableDirectToString(message: String?): String = Throwable(message).toString()

fun throwableAnyToString(message: String): String {
    val value: Any = Throwable(message)
    return value.toString()
}

fun throwableAsThrowableToString(message: String): String {
    val value: Throwable = Throwable(message)
    return value.toString()
}

fun throwableOverrideToString(): String = OverridingThrowable().toString()

fun throwableOverrideAsThrowableToString(): String {
    val value: Throwable = OverridingThrowable()
    return value.toString()
}

fun throwableOverrideAsAnyToString(): String {
    val value: Any = OverridingThrowable()
    return value.toString()
}

fun throwableSubclassToString(message: String): String = NamedThrowable(message).toString()

fun throwableCaughtToString(message: String): String =
    try {
        throw Throwable(message)
    } catch (error: Throwable) {
        error.toString()
    }

fun throwableWithCauseToString(): String =
    Throwable("outer", Throwable("inner")).toString()

fun throwableNoArgToString(): String = NoArgThrowable().toString()

fun throwableNoArgIsThrowable(): Boolean {
    val value: Any = NoArgThrowable()
    return value is Throwable
}

fun throwableMessageCauseToString(): String =
    MessageCauseThrowable("message", Throwable("cause")).toString()

fun throwableMessageCauseMessage(): String =
    MessageCauseThrowable("message", Throwable("cause")).message ?: "null"

fun throwableMessageCauseCause(): String =
    MessageCauseThrowable("message", Throwable("cause")).cause?.toString() ?: "null"

fun throwableStackTraceSize(): Int = Throwable("trace").getStackTrace().size
