interface Printer { fun print(msg: String) }
class ConsolePrinter : Printer { override fun print(msg: String) = println("Console: $msg") }
class DelegatingPrinter(printer: Printer) : Printer by printer
fun main() {
    val cp = ConsolePrinter()
    val dp = DelegatingPrinter(cp)
    dp.print("hello")
    cp.print("world")
}
