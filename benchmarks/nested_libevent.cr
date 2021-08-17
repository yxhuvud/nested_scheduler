require "../src/nested_scheduler"
require "http/server"

threads = ARGV.any? ? ARGV[0].to_i : 4

NestedScheduler::ThreadPool.nursery(threads) do |pl|
  pl.spawn(name: "serv") do
    server = HTTP::Server.new do |context|
      context.response.content_type = "text/plain"
      context.response.print "Hello world!"
    end

    address = server.bind_tcp 8080
    puts "Listening on http://#{address}"
    server.listen
  end
end
