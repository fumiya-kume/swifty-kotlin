import kotlin.coroutines.cancellation.CancellationException

fun main() {
    val noArg = CancellationException()
    val message = CancellationException("message")
    val cause = CancellationException(IllegalArgumentException("cause"))
    val messageAndCause = CancellationException("both", IllegalArgumentException("root"))

    println(noArg.message ?: "null")
    println(message.message ?: "null")
    println(cause.message ?: "null")
    println(cause.cause?.message ?: "null")
    println(messageAndCause.message ?: "null")
    println(messageAndCause.cause?.message ?: "null")
    println(messageAndCause is IllegalStateException)
    println(messageAndCause is Exception)
    println(messageAndCause is Throwable)
}
