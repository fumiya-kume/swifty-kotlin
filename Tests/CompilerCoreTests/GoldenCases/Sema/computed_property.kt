package golden.sema

class Widget {
    val computed: String get() = "hello"

    var backed: Int = 0
        get() = field
        set(value) { field = value }
}
