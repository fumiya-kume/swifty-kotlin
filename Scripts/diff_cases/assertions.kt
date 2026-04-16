// SKIP-DIFF: assert() is enabled by default in kswiftc runtime but disabled on the JVM
// reference (requires `-ea`), so stdout diverges. AssertionError/Error type catches now
// resolve in Sema; require/check/error cases pass parity.
fun main() {
    // assert passes when condition is true
    assert(true)
    assert(1 + 1 == 2) { "math still works" }

    // assert(false) throws AssertionError
    try {
        assert(false)
    } catch (e: AssertionError) {
        println("caught AssertionError: ${e.message}")
    }

    // assert with lazy message
    try {
        assert(false) { "custom assert message" }
    } catch (e: AssertionError) {
        println("caught AssertionError with message: ${e.message}")
    }

    // require throws IllegalArgumentException
    try {
        require(false)
    } catch (e: IllegalArgumentException) {
        println("caught IllegalArgumentException: ${e.message}")
    }

    // check throws IllegalStateException
    try {
        check(false)
    } catch (e: IllegalStateException) {
        println("caught IllegalStateException: ${e.message}")
    }

    // error throws IllegalStateException
    try {
        error("error message")
    } catch (e: IllegalStateException) {
        println("caught IllegalStateException from error: ${e.message}")
    }

    println("assertions-ok")
}
