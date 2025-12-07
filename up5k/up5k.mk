PIN_DEF ?= up5k/icesugar.pcf

DEVICE ?= up5k

BUILDDIR = bin

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	iceprog $^

$(BUILDDIR)/toplevel.json: $(VERILOG)
	mkdir -p $(BUILDDIR)
	yosys -l $(BUILDDIR)/yosys.log --debug -q -p "synth_ice40 -dsp -noabc9 -retime -abc2 -json $@" $^

$(BUILDDIR)/toplevel.asc: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ice40 --${DEVICE} --package sg48 --tmg-ripup --timing-allow-fail --freq 81 --asc $@ --json $(filter-out $<,$^) --pcf $<

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.asc
	icepack $^ $@

up5k/pll.v:
	icepll -n pll -p -i 12 -o 81 -m -f up5k/pll.v

clean:
	rm -rf ${BUILDDIR}

.SECONDARY:
.PHONY: compile clean prog
