import java.text.DecimalFormat
import java.text.NumberFormat
import java.util.Locale

fun main() {
    // DecimalFormat with pattern
    val df = DecimalFormat("#,##0.00")
    println(df.format(1234567.89))   // 1,234,567.89
    println(df.format(0.5))          // 0.50
    println(df.format(-9876.1))      // -9,876.10

    // DecimalFormat: integer-only pattern
    val dfInt = DecimalFormat("#,##0")
    println(dfInt.format(1000000))   // 1,000,000
    println(dfInt.format(42))        // 42

    // DecimalFormat: no grouping
    val dfNoGroup = DecimalFormat("0.000")
    println(dfNoGroup.format(3.14159))  // 3.142

    // NumberFormat.getNumberInstance
    val nf = NumberFormat.getNumberInstance(Locale.US)
    println(nf.format(1234.5))   // 1,234.5

    // NumberFormat.getCurrencyInstance
    val cf = NumberFormat.getCurrencyInstance(Locale.US)
    println(cf.format(9.99))     // $9.99

    // NumberFormat.getPercentInstance
    val pf = NumberFormat.getPercentInstance(Locale.US)
    println(pf.format(0.75))     // 75%

    // DecimalFormat.parse round-trip
    val df2 = DecimalFormat("#,##0.00")
    val parsed = df2.parse("1,234.56")
    println(parsed)  // 1234.56
}
