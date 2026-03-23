@DslMarker
annotation class HtmlDsl

@HtmlDsl
class HTML {
    var content = ""
    fun body(text: String) {
        content = text
    }
}

@HtmlDsl
class Body {
    var text = ""
    fun p(value: String) {
        text = value
    }
}

fun main() {
    val html = HTML()
    html.body("hello")
    println(html.content)
}
