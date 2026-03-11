package test

class Rect(val width: Int, val height: Int) {
    val area: Int
        get() = width * height

    var label: String = ""
        get() = field
        set(value) { field = value }
}
