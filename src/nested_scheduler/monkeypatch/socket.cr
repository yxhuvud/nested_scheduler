require "socket"

class Socket < IO
  # candidates:
  # require DNS:
  # def connect(host : String, port : Int, connect_timeout = nil)

  # def connect(addr, timeout = nil)
  # protected def accept_impl
  # def wait_acceptable
  # def send(message) : Int32
  # def send(message, to addr : Address) : Int32
  # protected def recvfrom(bytes)
  # private def shutdown(how) # doesnt
  # private def unbuffered_read(slice : Bytes)
  # private def unbuffered_write(slice : Bytes)
  # private def unbuffered_close
end
