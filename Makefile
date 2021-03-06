.PHONY : run all

all : run

run  :
	CRYSTAL_LOAD_DWARF=1 crystal spec -Dpreview_mt --error-trace

