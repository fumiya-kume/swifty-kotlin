fun main() {
    // 1. Basic onFailure: success case — action should NOT be called
    val success1 = runCatching { 42 }
    success1.onFailure { println("UNEXPECTED: onFailure called on success") }
    println("success onFailure done")

    // 2. Basic onFailure: failure case — action SHOULD be called
    val failure1 = runCatching { throw RuntimeException("boom") }
    failure1.onFailure { println("onFailure called: ${it.message}") }

    // 3. onSuccess on success result
    val chained = runCatching { 100 }
    chained.onSuccess { println("chained onSuccess: $it") }
    println("chained isSuccess: ${chained.isSuccess}")

    // 4. onFailure on failure result
    val chainedFail = runCatching { throw IllegalArgumentException("bad arg") }
    chainedFail.onFailure { println("chainedFail onFailure: ${it.message}") }
    println("chainedFail isFailure: ${chainedFail.isFailure}")

    // 5. getOrElse on success
    val successElse = runCatching { 42 }
    val elseVal = successElse.getOrElse { -1 }
    println("getOrElse success: $elseVal")

    // 6. getOrNull on failure
    val nullResult = runCatching { throw RuntimeException("null test") }
    val nullVal = nullResult.getOrNull()
    println("getOrNull result: $nullVal")

    // 7. onFailure does not consume the exception
    val exResult = runCatching { throw RuntimeException("still there") }
    exResult.onFailure { println("onFailure: ${it.message}") }
    println("exceptionOrNull: ${exResult.exceptionOrNull()?.message}")

    // 8. onSuccess value on success
    val succVal = runCatching { "hello" }
    succVal.onSuccess { println("onSuccess value: $it") }

    // 9. onFailure on failure
    val failChain = runCatching { throw RuntimeException("fail chain") }
    failChain.onFailure { println("onFailure in chain: ${it.message}") }

    // 10. onFailure on success does NOT trigger side effects
    val noSideEffect = runCatching { 1 }
    noSideEffect.onFailure { println("UNEXPECTED side effect") }
    println("sideEffect on success: false")

    // 11. getOrDefault on success
    val defaultResult = runCatching { 77 }
    println("getOrDefault: ${defaultResult.getOrDefault(99)}")

    // 12. isSuccess / isFailure
    val s = runCatching { 10 }
    val f = runCatching { throw RuntimeException("x") }
    println("s.isSuccess=${s.isSuccess} s.isFailure=${s.isFailure}")
    println("f.isSuccess=${f.isSuccess} f.isFailure=${f.isFailure}")
}
