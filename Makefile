.PHONY : run all

all : run

s :
	crystal spec -Dpreview_mt --error-trace spec/io_uring_context_spec.cr
le :
	crystal spec -Dpreview_mt --error-trace spec/libevent_context_spec.cr:30


run  :
	CRYSTAL_LOAD_DWARF=1 crystal spec -Dpreview_mt --error-trace

