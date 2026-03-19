fun main() {
    // Basic passing calls
    require(true)
    check(true)

    // Verify lazyMessage lambdas are not evaluated when condition is true
    var counter = 0
    require(true) { counter++; "should not fail" }
    check(true) { counter++; "should not fail" }
    println("lazy counter: $counter") // expect 0: lambdas were not called

    // Test require(false) throws IllegalArgumentException
    try {
        require(false) { "require failed" }
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    // Test check(false) throws IllegalStateException
    try {
        check(false) { "check failed" }
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    // Test error() throws IllegalStateException
    try {
        error("test error")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
