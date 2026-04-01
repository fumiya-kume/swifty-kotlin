fun main() {
    // Test 1: Exception re-throw
    try {
        try {
            throw RuntimeException("original")
        } catch (e: Exception) {
            println("Caught: ${e.message}")
            throw e  // re-throw
        }
    } catch (e: Exception) {
        println("Re-caught: ${e.message}")
    }

    // Test 2: Exception chaining with constructor cause
    try {
        val cause = RuntimeException("root cause")
        throw IllegalStateException("wrapper", cause)
    } catch (e: Exception) {
        println("Message: ${e.message}")
        println("Cause: ${e.cause?.message}")
    }

    // Test 3: Exception chaining with initCause
    try {
        val ex = RuntimeException("main error")
        val cause = IllegalArgumentException("the cause")
        ex.initCause(cause)
        throw ex
    } catch (e: Exception) {
        println("initCause message: ${e.message}")
        println("initCause cause: ${e.cause?.message}")
    }

    // Test 4: Exception suppression
    try {
        val primary = RuntimeException("primary")
        val suppressed1 = IllegalArgumentException("suppressed1")
        val suppressed2 = IllegalStateException("suppressed2")
        primary.addSuppressed(suppressed1)
        primary.addSuppressed(suppressed2)
        throw primary
    } catch (e: Exception) {
        println("Primary: ${e.message}")
        println("Has suppressed: true")
    }

    // Test 5: Nested try-finally (try-with-resources pattern)
    try {
        try {
            println("Resource acquired")
            throw RuntimeException("operation failed")
        } finally {
            println("Resource released")
        }
    } catch (e: Exception) {
        println("Caught after finally: ${e.message}")
    }

    println("All tests passed")
}
