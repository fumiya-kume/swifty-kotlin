interface Labeled

enum class Medal : Labeled { BRONZE, SILVER, GOLD }

fun classifyMedal(medal: Medal): String =
    if (medal is Medal) "enum-yes" else "enum-no"

fun classifyLabel(medal: Medal): String =
    if (medal is Labeled) "label-yes" else "label-no"

fun main() {
    println(Medal.BRONZE is Medal)
    println(Medal.BRONZE is Labeled)

    val medal: Medal = Medal.SILVER
    println(medal is Medal)
    println(medal is Labeled)

    println(classifyMedal(Medal.GOLD))
    println(classifyLabel(Medal.GOLD))

    println(Medal.BRONZE as Medal)
    println(Medal.SILVER as? Medal)
    println(Medal.GOLD as Labeled)
    println(Medal.BRONZE as? Labeled)
}
