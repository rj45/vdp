PIN_DEF ?= ulx3s/ulx3s_v20.lpf

DEVICE ?= 85k

BUILDDIR = bin

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	fujprog $^

$(BUILDDIR)/toplevel.json: $(VERILOG)
	mkdir -p $(BUILDDIR)
	yosys -l $(BUILDDIR)/yosys.log --debug -q -p "synth_ecp5 -abc2 -json $@" $^

$(BUILDDIR)/%.config: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ecp5 --${DEVICE} --package CABGA381 --speed 6 --tmg-ripup --timing-allow-fail --freq 25 --textcfg  $@ --json $(filter-out $<,$^) --lpf $<

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.config
	ecppack --compress $^ $@

ulx3s/pll.v:
	ecppll -n pll -i 25 --clkout0_name clk_pix5x -o 300 --clkout1_name clk_pix --clkout1 60 --clkout2_name clk_draw --clkout2 60 -f ulx3s/pll.v

clean:
	rm -rf ${BUILDDIR}

.SECONDARY:
.PHONY: compile clean prog
