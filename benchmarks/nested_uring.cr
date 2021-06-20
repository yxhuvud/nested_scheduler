require "../src/nested_scheduler"
require "http/server"

class HTTP::Server
  # Starts the server. Blocks until the server is closed.
  def listen
    raise "Can't re-start closed server" if closed?
    raise "Can't start server with no sockets to listen to, use HTTP::Server#bind first" if @sockets.empty?
    raise "Can't start running server" if listening?

    @listening = true
    done = Channel(Nil).new

    @sockets.each do |socket|
      spawn do
        until closed?
          io =
            begin
              socket.accept?
            rescue e
              handle_exception(e)
              nil
            end

          if io
            # a non nillable version of the closured io
            _io = io
            spawn handle_client(_io)
          end
        end
      ensure
        done.send nil
      end
    end

    @sockets.size.times { done.receive }
  end
end

class TCPServer
    # Binds a socket to the *host* and *port* combination.
  def initialize(host : String, port : Int, backlog : Int = SOMAXCONN, dns_timeout = nil, reuse_port : Bool = false)
    Addrinfo.tcp(host, port, timeout: dns_timeout) do |addrinfo|
      super(addrinfo.family, addrinfo.type, addrinfo.protocol)

      self.reuse_address = true
      self.reuse_port = true if reuse_port

      if errno = bind(addrinfo, "#{host}:#{port}") { |errno| errno }
        close
        next errno
      end

      if errno = listen(backlog) { |errno| errno }
        close
        next errno
      end
    end
  end
end


NestedScheduler::ThreadPool.nursery(32, io_context: NestedScheduler::IoUringContext.new) do |pl|
  pl.spawn do
    server = HTTP::Server.new do |context|
      context.response.content_type = "text/plain"
      context.response.print "Hello world!"
    end

    address = server.bind_tcp 8080
    puts "Listening on http://#{address}"
    server.listen
  end
end
