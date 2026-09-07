fun main() {
    val beforeNext = mutableMapOf("before" to 1).iterator()
    try {
        beforeNext.remove()
        println("before-next: not-thrown")
    } catch (e: IllegalStateException) {
        println("before-next: caught")
    }

    val afterRemove = mutableMapOf("after" to 2).iterator()
    afterRemove.next()
    afterRemove.remove()
    try {
        afterRemove.remove()
        println("double-remove: not-thrown")
    } catch (e: IllegalStateException) {
        println("double-remove: caught")
    }
}
