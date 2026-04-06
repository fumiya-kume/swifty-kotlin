// REPLのような逐次実行を模倣
println("Starting interactive session...")

val session = mutableMapOf<String, Any>()

session["counter"] = 0
println("counter = ${session["counter"]}")

session["counter"] = (session["counter"] as Int) + 1
println("counter = ${session["counter"]}")

session["message"] = "Hello REPL"
println("message = ${session["message"]}")

val history = mutableListOf<String>()
history.add("Set counter to 0")
history.add("Incremented counter")
history.add("Set message")
println("History: ${history.joinToString()}")
