fun main() {
    var counter = 0

    require(true) { counter += 1; "require should not run" }
    check(true) { counter += 10; "check should not run" }
    println(counter)

    try {
        require(false) { "bad-arg" }
    } catch (e: Throwable) {
        println(e.message)
    }

    try {
        check(false) { "bad-state" }
    } catch (e: Throwable) {
        println(e.message)
    }

    try {
        error("boom")
    } catch (e: Throwable) {
        println(e.message)
    }
}
