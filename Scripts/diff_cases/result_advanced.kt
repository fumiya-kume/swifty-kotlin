fun main() {
    // 1. recoverCatching on failure — transform succeeds
    val fail1 = runCatching { throw RuntimeException("original") }
    val rec1 = fail1.recoverCatching { -1 }
    println("recoverCatching success: ${rec1.getOrNull()}")
    println("recoverCatching isSuccess: ${rec1.isSuccess}")

    // 2. recoverCatching on success — passes through
    val succ1 = runCatching { 42 }
    val rec2 = succ1.recoverCatching { -1 }
    println("recoverCatching passthrough: ${rec2.getOrNull()}")

    // 3. recoverCatching on failure — transform itself throws
    val fail2 = runCatching { throw RuntimeException("fail2") }
    val rec3 = fail2.recoverCatching { throw RuntimeException("transform threw") }
    println("recoverCatching transform threw isFailure: ${rec3.isFailure}")

    // 4. recover on failure — basic
    val fail3 = runCatching { throw RuntimeException("recover me") }
    val rec4 = fail3.recover { 99 }
    println("recover value: ${rec4.getOrNull()}")
    println("recover isSuccess: ${rec4.isSuccess}")

    // 5. recover on success — passes through
    val succ2 = runCatching { 77 }
    val rec5 = succ2.recover { 0 }
    println("recover passthrough: ${rec5.getOrNull()}")

    // 6. component1 on success
    val succ3 = runCatching { 123 }
    val v1 = succ3.component1()
    println("component1 success: $v1")

    // 7. component2 on success — should be null
    val succ4 = runCatching { 456 }
    val e1 = succ4.component2()
    println("component2 success null: ${e1 == null}")

    // 8. component1 on failure — should be null
    val fail4 = runCatching { throw RuntimeException("comp test") }
    val v2 = fail4.component1()
    println("component1 failure null: ${v2 == null}")

    // 9. component2 on failure
    val fail5 = runCatching { throw RuntimeException("comp2 test") }
    val e2 = fail5.component2()
    println("component2 failure: ${e2?.message}")

    // 10. onSuccess on success
    val succ5 = runCatching { 10 }
    succ5.onSuccess { println("onSuccess: $it") }

    // 11. onFailure on failure
    val fail6 = runCatching { throw RuntimeException("side effect") }
    fail6.onFailure { println("onFailure: ${it.message}") }

    // 12. chained onSuccess + onFailure
    runCatching { 5 }
        .onSuccess { println("chain success: $it") }
        .onFailure { println("chain fail unexpected") }

    runCatching { throw RuntimeException("chain err") }
        .onSuccess { println("chain2 success unexpected") }
        .onFailure { println("chain2 fail: ${it.message}") }
}
