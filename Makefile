.PHONY : run all

all : run

run  :
	crystal spec -Dpreview_mt --error-trace

