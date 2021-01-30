# abstract class IO
#   def read_fully?(slice : Bytes)
#     s = "read fully: #{slice.size}\n"
#     LibC.write(STDOUT.fd, s.to_unsafe, s.size)

#     count = slice.size
#     while slice.size > 0
#       read_bytes = read slice
#       return nil if read_bytes == 0
#       slice += read_bytes
#     end
#     s = "done\n"
#     LibC.write(STDOUT.fd, s.to_unsafe, s.size)

#     count
#   end

# end
