fun describe(v: Any): String {
    if (v is String && v.length > 2) {
        return "long"
    }
    if (v !is String || v.length == 0) {
        return "other"
    }
    return "short"
}

fun lengthIfString(v: Any): Int {
    if (v !is String) {
        return -1
    } else {
        return v.length
    }
}

fun main() {
    println(describe("kotlin"))
    println(describe(""))
    println(describe(42))
    println(lengthIfString("abc"))
    println(lengthIfString(0))
}
