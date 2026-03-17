fun main() {
    require(true)
    require(true) { "should not fail" }
    check(true)
    check(true) { "should not fail" }
    try { require(false) } catch (e: IllegalArgumentException) { println(e.message) }
    try { check(false) } catch (e: IllegalStateException) { println(e.message) }
    try { error("test error") } catch (e: IllegalStateException) { println(e.message) }
}
