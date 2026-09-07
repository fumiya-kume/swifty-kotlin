private class NamedThrowable(message: String?) : Throwable(message)

private class NoArgThrowable : Throwable()

private class MessageCauseThrowable(message: String?, cause: Throwable?) : Throwable(message, cause)

private class OverridingThrowable : Throwable("base") {
    override fun toString(): String = "override"
}

private fun hasSuffix(value: String, suffix: String): Boolean = value.endsWith(suffix)

private fun directToString(message: String?): String = Throwable(message).toString()

private fun anyToString(message: String): String {
    val value: Any = Throwable(message)
    return value.toString()
}

private fun throwableToString(message: String): String {
    val value: Throwable = Throwable(message)
    return value.toString()
}

private fun overridingToString(): String = OverridingThrowable().toString()

private fun overridingAsThrowableToString(): String {
    val value: Throwable = OverridingThrowable()
    return value.toString()
}

private fun overridingAsAnyToString(): String {
    val value: Any = OverridingThrowable()
    return value.toString()
}

private fun caughtToString(message: String): String =
    try {
        throw Throwable(message)
    } catch (error: Throwable) {
        error.toString()
    }

private fun stackTraceSummary(): String {
    val frames = Throwable("trace").getStackTrace()
    val firstFramePresent = frames.size > 0 && frames[0].toString().isNotEmpty()
    return "${frames.size > 0}:$firstFramePresent:${if (frames.size == 0) "empty" else "nonempty"}"
}

fun main() {
    val nullMessage = directToString(null)
    val emptyMessage = directToString("")
    val message = directToString("message")
    val withCause = Throwable("outer", Throwable("inner")).toString()
    val overridden = overridingToString()
    val overriddenAsThrowable = overridingAsThrowableToString()
    val overriddenAsAny = overridingAsAnyToString()
    val noArg = NoArgThrowable()
    val noArgAny: Any = noArg
    val cause = Throwable("cause")
    val messageCause = MessageCauseThrowable("message", cause)
    val messageCauseAny: Any = messageCause

    println(nullMessage)
    println(emptyMessage)
    println(message)
    println(anyToString("any"))
    println(throwableToString("base"))
    println(NamedThrowable("subclass").toString())
    println(caughtToString("caught"))
    println(withCause)
    println(overridden)
    println(overriddenAsThrowable)
    println(overriddenAsAny)
    println(noArg.toString())
    println(noArg.message ?: "null")
    println(noArg.cause?.toString() ?: "null")
    println(noArgAny.toString())
    println(noArgAny is Throwable)
    println(messageCause.toString())
    println(messageCause.message ?: "null")
    println(messageCause.cause?.toString() ?: "null")
    println(messageCauseAny.toString())
    println(messageCauseAny is Throwable)
    println(hasSuffix(nullMessage, "Throwable"))
    println(hasSuffix(emptyMessage, "Throwable: "))
    println(hasSuffix(message, "Throwable: message"))
    println(hasSuffix(anyToString("any"), "Throwable: any"))
    println(hasSuffix(throwableToString("base"), "Throwable: base"))
    println(hasSuffix(NamedThrowable("subclass").toString(), "NamedThrowable: subclass"))
    println(hasSuffix(caughtToString("caught"), "Throwable: caught"))
    println(hasSuffix(withCause, "Throwable: outer"))
    println(hasSuffix(overridden, "override"))
    println(hasSuffix(overriddenAsThrowable, "override"))
    println(hasSuffix(overriddenAsAny, "override"))
    println(hasSuffix(noArg.toString(), "NoArgThrowable"))
    println(noArg.message == null)
    println(noArg.cause == null)
    println(hasSuffix(messageCause.toString(), "MessageCauseThrowable: message"))
    println(messageCause.message == "message")
    println(messageCause.cause === cause)
    println(messageCauseAny is Throwable)
    println(stackTraceSummary())
}
