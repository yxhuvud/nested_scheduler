module NestedScheduler
  # Same as Thread::LinkedList(T) but with different field names.
  # There is a need of a list per thread pool in addition to the
  # global one. Potentially it could be changed so that there isn't
  # any global list of fibers but only one list per pool (probably a
  # good idea - if there is many fibers then deletion becomes a
  # bottleneck due to it being O(n)). In that case it might be a good
  # idea to instead have Thread::LinkedList of pools for fiber
  # iteration purpose. It would probably make it easier to get an idea
  # of what a system is doing.
  class LinkedList2(T)
    @mutex = Thread::Mutex.new
    @head : T?
    @tail : T?

    # Iterates the list without acquiring the lock, to avoid a deadlock in
    # stop-the-world situations, where a paused thread could have acquired the
    # lock to push/delete a node, while still being "safe" to iterate (but only
    # during a stop-the-world).
    def unsafe_each : Nil
      node = @head

      while node
        yield node
        node = node.next2
      end
    end

    # Appends a node to the tail of the list. The operation is thread-safe.
    #
    # There are no guarantees that a node being pushed will be iterated by
    # `#unsafe_each` until the method has returned.
    def push(node : T) : Nil
      @mutex.synchronize do
        node.previous2 = nil

        if tail = @tail
          node.previous2 = tail
          @tail = tail.next2 = node
        else
          @head = @tail = node
        end
      end
    end

    # Removes a node from the list. The operation is thread-safe.
    #
    # There are no guarantees that a node being deleted won't be iterated by
    # `#unsafe_each` until the method has returned.
    def delete(node : T) : Nil
      @mutex.synchronize do
        if previous = node.previous2
          previous.next2 = node.next2
        else
          @head = node.next2
        end

        if _next = node.next2
          _next.previous2 = node.previous2
        else
          @tail = node.previous2
        end
      end
    end
  end
end
