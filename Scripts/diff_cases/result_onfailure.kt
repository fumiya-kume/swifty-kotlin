// SKIP-DIFF — Result.success/failure companion factory not yet lowered
fun main() {
    val success = Result.success(42)
    val failure = Result.failure<Int>(RuntimeException("error"))
    success.onFailure { println("should not print") }.onSuccess { println("success: $it") }
    failure.onSuccess { println("should not print") }.onFailure { println("failure: ${it.message}") }
    println(success.getOrNull())
    println(failure.getOrNull())
    println(success.getOrElse { 0 })
    println(failure.getOrElse { 0 })
}
