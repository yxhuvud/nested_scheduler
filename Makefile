.PHONY : clean run all

all : clean run

clean :
	rm -rf ./test/*

s :
	crystal spec -Dpreview_mt --error-trace spec/io_uring_context_spec.cr
le :
	crystal spec -Dpreview_mt --error-trace spec/libevent_context_spec.cr:30


run  :
	CRYSTAL_LOAD_DWARF=1 crystal spec -Dpreview_mt --error-trace

