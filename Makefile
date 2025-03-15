VERILOG = ulx3s/pll.v rtl/vga.sv rtl/hdmi.v rtl/palette_bram.sv \
          rtl/linebuffer_bram.sv rtl/double_buffer.sv rtl/pixel_doubler.sv \
		  rtl/smoldvi.v rtl/smoldvi_clock_driver.v rtl/smoldvi_fast_gearbox.v \
		  rtl/smoldvi_serializer.v rtl/smoldvi_tmds_encode.v \
		  rtl/shift_aligner.sv rtl/tile_bram.sv rtl/main.sv ulx3s/top_ulx3s.sv

TESTS = bin/pixel_doubler_tb

PIN_DEF = ulx3s/ulx3s_v20.lpf

include ulx3s/ulx3s.mk

lint: $(VERILOG)
	verilator --lint-only -Wall $^

test: $(TESTS)

bin/%_tb: rtl/%.sv rtl/%_tb.sv
	mkdir -p bin
	iverilog -g2005-sv -o $@ $^
	vvp $@
