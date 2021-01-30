require "./spec_helper"

# Mostly of it simply copied from Crystal stdlib Socket specs.

def unused_local_port
  TCPServer.open("::", 0) do |server|
    server.local_address.port
  end
end

def each_ip_family(&block : Socket::Family, String, String ->)
  describe "using IPv4" do
    block.call Socket::Family::INET, "127.0.0.1", "0.0.0.0"
  end

  describe "using IPv6" do
    block.call Socket::Family::INET6, "::1", "::"
  end
end

describe NestedScheduler::IoUringContext do
  pending "HANDLES MULTIPLE WORKING THREADS (NOT)"

  it "works with enclosing scope" do
    run = false

    NestedScheduler::ThreadPool.nursery(1, io_context: NestedScheduler::IoUringContext.new, name: "uring") do |pl|
      pl.spawn do
        run = true
      end
    end
    run.should be_true
  end

  # it "works with channels" do
  #   done = Channel(Nil).new(1)

  #   NestedScheduler::ThreadPool.nursery(1, io_context: NestedScheduler::IoUringContext.new, name: "uring") do |pl|
  #     pl.spawn do
  #       done.send nil
  #     end
  #   end
  #   done.receive.should be_nil
  # end

  # it "#accept" do
  #   client_done = Channel(Nil).new
  #   server = Socket.new(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP)
  #   begin
  #     port = unused_local_port
  #     server.bind("0.0.0.0", port)
  #     server.listen

  #     spawn do
  #       TCPSocket.new("127.0.0.1", port).close
  #     ensure
  #       client_done.send nil
  #     end

  #     NestedScheduler::ThreadPool.nursery(1, io_context: NestedScheduler::IoUringContext.new, name: "uring") do |pl|
  #       pl.spawn name: "uring_context" do
  #         p :no_accept
  #         # client = server.accept
  #         # p :accepted
  #         # begin
  #         #   client.family.should eq(Socket::Family::INET)
  #         #   client.type.should eq(Socket::Type::STREAM)
  #         #   client.protocol.should eq(Socket::Protocol::TCP)
  #         # ensure
  #         #   client.close
  #         # end
  #         #          p :fiber_done
  #       end
  #     end
  #     p :done
  #   ensure
  #     server.close
  #     client_done.receive
  #   end
  # end

  # it "sends messages" do
  #   port = unused_local_port
  #   server = Socket.tcp(Socket::Family::INET6)
  #   server.bind("::1", port)
  #   server.listen
  #   address = Socket::IPAddress.new("::1", port)
  #   spawn do
  #     client = server.not_nil!.accept
  #     client.gets.should eq "foo"
  #     client.puts "bar"
  #   ensure
  #     client.try &.close
  #   end
  #   socket = Socket.tcp(Socket::Family::INET6)
  #   socket.connect(address)
  #   socket.puts "foo"
  #   socket.gets.should eq "bar"
  # ensure
  #   socket.try &.close
  #   server.try &.close
  # end

  # each_ip_family do |family, address, unspecified_address|
  #   it "sends and receives messages" do
  #     port = unused_local_port

  #     server = UDPSocket.new(family)
  #     server.bind(address, port)
  #     server.local_address.should eq(Socket::IPAddress.new(address, port))

  #     client = UDPSocket.new(family)
  #     client.bind(address, 0)

  #     client.send "message", to: server.local_address
  #     server.receive.should eq({"message", client.local_address})

  #     client.connect(address, port)
  #     client.local_address.family.should eq(family)
  #     client.local_address.address.should eq(address)
  #     client.remote_address.should eq(Socket::IPAddress.new(address, port))

  #     client.send "message"
  #     server.receive.should eq({"message", client.local_address})

  #     client.send("laus deo semper")

  #     buffer = uninitialized UInt8[256]

  #     bytes_read, client_addr = server.receive(buffer.to_slice)
  #     message = String.new(buffer.to_slice[0, bytes_read])
  #     message.should eq("laus deo semper")

  #     client.send("laus deo semper")

  #     bytes_read, client_addr = server.receive(buffer.to_slice[0, 4])
  #     message = String.new(buffer.to_slice[0, bytes_read])
  #     message.should eq("laus")

  #     client.close
  #     server.close
  #   end
  # end
end
