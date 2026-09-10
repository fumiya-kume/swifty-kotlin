private fun firstNonLocal(source: CharSequence): Char {
    source.first {
        if (it == 'x') return '!'
        false
    }
    return '?'
}

fun main() {
    println(firstNonLocal("ax").code)
}
