module NestedScheduler #struct?
  abstract class IOContext
    abstract def new
  end
  
  class LibeventContext < IOContext
    def new
      self
    end
  end
end
