fun testAssociateTo(values: List<String>) {
    val dest1 = mutableMapOf<String, Int>()
    val result1 = values.associateTo(dest1) { it to it.length }
    println(result1)
}

fun testAssociateByTo(values: List<String>) {
    val dest2 = mutableMapOf<Int, String>()
    val result2 = values.associateByTo(dest2) { it.length }
    println(result2)
}

fun testAssociateWithTo(values: List<String>) {
    val dest3 = mutableMapOf<String, Int>()
    val result3 = values.associateWithTo(dest3) { it.length }
    println(result3)
}

fun testGroupByTo(values: List<String>) {
    val dest4 = mutableMapOf<Int, MutableList<String>>()
    val result4 = values.groupByTo(dest4) { it.length }
    println(result4)
}
