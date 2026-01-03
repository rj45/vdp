## Project F: FPGA Graphics - Verilator Sim Makefile
## (C)2023 Will Green, open source hardware released under the MIT License
## Learn more at https://projectf.io/posts/fpga-graphics/

VFLAGS = -O3 --x-assign fast --x-initial fast --noassert --threads 1 --compiler gcc
SDL_CFLAGS = `sdl2-config --cflags`
SDL_LDFLAGS = `sdl2-config --libs`

test: test.exe

%.exe: %.mk
	make -C ./obj_dir -f Vtop_$<

%.mk: top_%.sv
	cp ../rtl/*.hex .
	verilator ${VFLAGS} -I../rtl -I../rtl/fpgacpu_ca \
		-cc $< --exe main_$(basename $@).cpp sdram.cpp -o $(basename $@) \
		-CFLAGS "${SDL_CFLAGS} -std=c++17 -march=native -fstrict-aliasing -O3 -flto" -LDFLAGS "${SDL_LDFLAGS} -flto"

all: test

run: test
	./obj_dir/test

clean:
	rm -rf ./obj_dir

.PHONY: all clean
