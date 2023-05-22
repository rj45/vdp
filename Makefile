VERILOG = ulx3s/pll.v rtl/vga.sv rtl/hdmi.v rtl/palette_bram.sv \
          rtl/linebuffer_bram.sv rtl/double_buffer.sv \
		  rtl/main.sv ulx3s/top_ulx3s.sv

TESTS = bin/pixel_quadrupler_tb

PIN_DEF = ulx3s/ulx3s_v20.lpf

include ulx3s/ulx3s.mk

test: $(TESTS)

bin/%_tb: rtl/%.sv rtl/%_tb.sv
	mkdir bin
	iverilog -g2005-sv -o $@ $^
	vvp $@
