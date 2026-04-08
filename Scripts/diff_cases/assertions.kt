// SKIP-DIFF: exception type catch clauses (AssertionError, IllegalArgumentException, IllegalStateException) not yet supported
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
