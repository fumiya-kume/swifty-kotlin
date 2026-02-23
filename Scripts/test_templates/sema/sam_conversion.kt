package golden.sema

fun interface Action {
    fun run()
}

fun execute(action: Action) = action.run()

fun useSam() {
    execute { println("hello") }
}
