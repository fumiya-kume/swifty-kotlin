interface Logger { fun log(msg: String) }
object ConsoleLogger : Logger {
    override fun log(msg: String) = println("LOG: $msg")
    var count = 0
}
fun doWork(logger: Logger) {
    logger.log("working")
    ConsoleLogger.count++
}
fun main() {
    doWork(ConsoleLogger)
    doWork(ConsoleLogger)
    println("count: ${ConsoleLogger.count}")
}
