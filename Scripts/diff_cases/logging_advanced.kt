fun main() {
    // MDC basic usage
    println("=== MDC ===")
    MDC.put("requestId", "abc-123")
    MDC.put("userId", "42")
    println("requestId: ${MDC.get("requestId")}")
    println("userId: ${MDC.get("userId")}")
    println("missing: ${MDC.get("unknown")}")
    MDC.remove("userId")
    println("after remove userId: ${MDC.get("userId")}")
    MDC.clear()
    println("after clear requestId: ${MDC.get("requestId")}")

    // Advanced logger basic usage
    println("=== Advanced Logger ===")
    val logger = AdvancedLogger.getLogger("com.example.MyService")
    logger.setLevel("INFO")
    logger.log("INFO", "Starting service")
    logger.log("WARNING", "Low memory")
    logger.log("SEVERE", "Fatal error")

    // Level filtering — FINE should be suppressed
    logger.setLevel("WARNING")
    logger.log("FINE", "This should be filtered out")
    logger.log("WARNING", "Visible warning")
    logger.setLevel("INFO")

    // Package filter — only loggers under com.example should emit
    val otherLogger = AdvancedLogger.getLogger("org.other.Module")
    otherLogger.setPackageFilter("com.example")
    otherLogger.log("INFO", "This should be filtered by package")
    logger.setPackageFilter("com.example")
    logger.log("INFO", "This should pass package filter")
    logger.clearPackageFilter()

    // Structured (JSON) output to stdout
    println("=== Structured Logging ===")
    val jsonLogger = AdvancedLogger.getLogger("com.example.JsonService")
    val jsonAppender = StructuredAppender.stdout()
    jsonLogger.addStructuredAppender(jsonAppender)
    MDC.put("traceId", "xyz-789")
    jsonLogger.log("INFO", "Order placed")
    MDC.clear()

    println("OK")
}
