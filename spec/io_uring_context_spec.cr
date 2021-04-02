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

def nursery
  NestedScheduler::ThreadPool.nursery(1, io_context: NestedScheduler::IoUringContext.new, name: "uring") do |pl|
    yield pl
  end
end

describe NestedScheduler::IoUringContext do
  pending "HANDLES MULTIPLE WORKING THREADS (NOT)"

  it "works with enclosing scope" do
    run = false

    nursery do |pl|
      pl.spawn { run = true }
    end
    run.should be_true
  end

  describe "write" do
    it "Can write to stdout" do
      # nice for error printing ..
      # kernel 5.8 is not enough for this. 5.11 is, so it was fixed at some point.
      nursery do |pl|
        pl.spawn { puts }
      end
    end

    it "write" do
      filename = "test/write1"
      nursery do |pl|
        pl.spawn { File.write filename, "hello world" }
      end
      File.read("test/write1").should eq "hello world"
    end
  end

  it "works with channels" do
    done = Channel(Nil).new(1)

    nursery do |pl|
      pl.spawn { done.send nil }
    end
    done.receive.should be_nil
  end

  describe "#accept" do
    it "can accept" do
      port = unused_local_port
      server = Socket.new(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP)
      server.bind("0.0.0.0", port)
      server.listen

      spawn { TCPSocket.new("127.0.0.1", port).close }

      client = nil
      nursery do |pl|
        pl.spawn { client = server.accept }
      end

      # expectations outside spawn block just to be sure it runs.
      client.not_nil!.family.should eq(Socket::Family::INET)
      client.not_nil!.type.should eq(Socket::Type::STREAM)
      client.not_nil!.protocol.should eq(Socket::Protocol::TCP)

      client.not_nil!.close
      server.close
    end

    pending "handles timeout"
  end

  describe "write" do
    it "Can write to stdout" do
      # nice for error printing ..
      # kernel 5.8 is not enough for this. 5.11 is, so it was fixed at some point.
      NestedScheduler::ThreadPool.nursery(1, io_context: NestedScheduler::IoUringContext.new, name: "uring") do |pl|
        pl.spawn { puts }
      end
    end

    it "write" do
      filename = "test/write1"
      NestedScheduler::ThreadPool.nursery(1, io_context: NestedScheduler::IoUringContext.new, name: "uring") do |pl|
        pl.spawn { File.write filename, "hello world" }
      end
      File.read("test/write1").should eq "hello world"
    end
  end
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
