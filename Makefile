BOARD ?= up5k
# BOARD = ulx3s

VERILOG = rtl/main.sv $(BOARD)/pll.v rtl/vga.sv rtl/hdmi.v rtl/palette_bram.sv \
          rtl/linebuffer_bram.sv rtl/double_buffer.sv rtl/pixel_doubler.sv \
		  rtl/tile_map_bram.sv rtl/sprite_bram.sv \
		  rtl/smoldvi.v rtl/smoldvi_clock_driver.v rtl/smoldvi_fast_gearbox.v \
		  rtl/smoldvi_serializer.v rtl/smoldvi_tmds_encode.v \
		  rtl/fpgacpu_ca/cdc_bit_synchronizer.sv rtl/fpgacpu_ca/pulse_generator.sv \
		  rtl/fpgacpu_ca/cdc_pulse_synchronizer_2phase.sv rtl/fpgacpu_ca/register.sv \
		  rtl/fpgacpu_ca/register_toggle.sv \
		  rtl/shift_aligner.sv rtl/tile_bram.sv $(BOARD)/top_$(BOARD).sv

TESTS = bin/pixel_doubler_tb

include $(BOARD)/$(BOARD).mk

lint: $(VERILOG)
	verilator --lint-only -Wall $^

test: $(TESTS)

bin/%_tb: rtl/%.sv rtl/%_tb.sv
	mkdir -p bin
	iverilog -g2005-sv -o $@ $^
	vvp $@
