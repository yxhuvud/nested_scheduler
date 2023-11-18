require "crystal/system/event_loop"

abstract class Crystal::EventLoop
  def stop
  end
end

class Crystal::LibEvent::EventLoop
  def stop
    event_base.stop
  end
end

struct Crystal::LibEvent::Event::Base
  def stop : Nil
    LibEvent2.event_base_free(@base)
  end
end

lib LibEvent2
  fun event_base_free(event : EventBase) : Nil
end
