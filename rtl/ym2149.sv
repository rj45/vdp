//
// YM-2149 / AY-3-8910 Complex Sound Generator
// Matthew Hagerty
// June 2020
// https://dnotq.io
// https://github.com/dnotq/ym2149_audio/blob/master/rtl/ym2149_audio.vhd
//

// Released under the 3-Clause BSD License:
//
// Copyright 2020 Matthew Hagerty (matthew <at> dnotq <dot> io)
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
// contributors may be used to endorse or promote products derived from this
// software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

//
// This core is based mostly on the YM-2149 Programmable Sound Generator (PSG),
// which is an upgraded version of the AY-3-8913 PSG.  The main changes in the
// YM-2149 over the AY-3-8910 are:
//
//   * 5-bit envelope shape counter for smoother volume ramping, with 1.5dB
//     logarithmic steps.
//   * simplified host interface, i.e. no BC2 input.
//   * option to divide the input clock in half prior to further dividing.
//
//
// TODO: Currently the two external 8-bit I/O ports are not implemented.
// Their implementation should be easy enough, so it will probably happen in
// the future when a system that uses the I/O is implemented (they would need
// to be tested, and the SoC that this core was initially written for does not
// use the PSG's I/O ports).

// A huge amount of effort has gone into making this core as accurate as
// possible to the real IC, while at the same time making it usable in all-
// digital SoC designs, i.e. retro-computer and game systems, etc.  Design
// elements from the real IC were used and implemented when possible, with any
// work-around or changes noted along with the reasons.
//
// Synthesized and FPGA proven:
//
//   * Xilinx Spartan-6 LX16, SoC 25.0MHz system clock, 3.58MHz clock-enable.
//
//
// References:
//
//   * The AY-3-8910 die-shot and reverse engineered schematic.  This was the
//     most beneficial reference and greatly appreciated!  Removes any questions
//     about what the real IC does.
//     https://github.com/lvd2/ay-3-8910_reverse_engineered
//   * The YM-2149 and AY-3-8910 datasheets.
//   * Real YM-2149 IC.
//   * Chip quirks, use, and abuse details from friends and retro enthusiasts.
//
//
// Generates:
//
//   * Unsigned 12-bit output for each channel.
//   * Unsigned 14-bit summation of the channels.
//   * Signed 14-bit PCM summation of the channels, with each channel
//     converted to -/+ zero-centered level or -/+ full-range level.
//
// The tone counters are period-limited to prevent the very high frequency
// outputs that the original IC is capable of producing.  Frequencies above
// 20KHz cause problems in all-digital systems with sampling rates around
// 44.1KHz to 48KHz.  The primary use of these high frequencies was as a
// carrier for amplitude modulated (AM) audio.  The high frequency would be
// filtered out by external electronics, leaving only the low frequency audio.
//
// When the tone counters are limited, the normal square-wave is set to always
// output a '1', but the amplitude can still be changed, which allows the A.M.
// technique to still work in a digital Soc.
//

// Clock, Clock-enable, and Sel.
//
// The clk_i input should be the full-speed clock of the system, and
// en_clk_psg_i must be a strobe (single clk_i tick) at the PSG operating
// frequency.
//
// If the sel_n_i input is used to divide the en_clk_psg_i strobe, the host
// interface will continue to operate with the non-divided en_clk_psg_i strobe.
//
// sel_n_i          :    0       1
// en_clk_psg_i max :  4.0MHz  2.0MHz
//
// This core can use a much faster clock-enable than the original PSG, however
// the clock-enable frequency affects the output audio frequency directly.  If
// producing sounds similar to the original ICs is desired, then using an
// accurate input clock-enable is important.
//
// In circuits where these PSG ICs were used, the clocks tend to be derived
// from division of the video clock frequency, and generally fell very close to
// a frequency of 1.78MHz.
//
// Internally the PSG divides the clock by 3 or 4 to obtain a typical internal
// operating frequency of around 447KHz.  Some PSGs take this lower frequency
// directly, but most do clock division internally to reduce the external
// components needed by a designed using the PSG IC.
//
// Common frequencies found in retro systems:
//
//  Crystal        Pixel          CPU            PSG        other PSG
// 10.738MHz  /2 = 5.369MHz  /3 = 3.579MHz  /6 = 1.789MHz /24 = 447.437KHz
// 14.318MHz  /2 = 7.159MHz  /4 = 3.579MHz  /8 = 1.789MHz
// 21.477MHz  /2 =10.738MHz  /6 = 3.579MHz /12 = 1.789MHz
//
// A pixel clock of 5.369MHz is common for NTSC, and 7.159MHz is common for
// standard resolution arcade games.
//

// Basic host interface, uses the simplified form where BC2 is not used or
// exposed externally (AY-3-8913).
//
//   BDIR  BC1     State
//     0    0    Inactive
//     0    1    Read from PSG
//     1    0    Write to PSG
//     1    1    Latch address
//

//
// Version history:
//
// June 28 2020
//   V1.0.  Release.  SoC tested.
//


module ym2149 #(
    // Non-custom PSG address mask is 0000.
    parameter logic [3:0] ADDRESS_G = 4'h0
) (
    input  logic        clk_i,              // system clock
    input  logic        en_clk_psg_i,       // PSG clock enable
    input  logic        sel_n_i,            // divide select, 0=clock-enable/2
    input  logic        reset_n_i,          // active low
    input  logic        bc_i,               // bus control
    input  logic        bdir_i,             // bus direction
    input  logic [7:0]  data_i,
    output logic [7:0]  data_r_o,           // registered output data
    output logic [11:0] ch_a_o,
    output logic [11:0] ch_b_o,
    output logic [11:0] ch_c_o,
    output logic [13:0] mix_audio_o,
    output logic [13:0] pcm14s_o
);

    // Registered inputs.
    logic [3:0]  reg_addr_r = 4'h0;
    logic [3:0]  reg_addr_x;
    logic [7:0]  data_i_r = 8'h00;
    logic [7:0]  data_o_r = 8'h00;
    logic [1:0]  busctl_r = 2'b00;
    logic        sel_n_r = 1'b1;
    logic        sel_ff_r = 1'b1;
    logic        sel_ff_x;
    logic        en_int_clk_psg_s;

    // Register file, should infer to discrete flip-flops.
    logic [7:0]  reg_file_ar [0:15];

    logic        en_data_rd_s;
    logic        en_data_wr_s;

    // Channel DAC levels.
    logic [11:0] ch_a_level_r = 12'h0;
    logic [11:0] ch_a_level_x;
    logic [11:0] ch_b_level_r = 12'h0;
    logic [11:0] ch_b_level_x;
    logic [11:0] ch_c_level_r = 12'h0;
    logic [11:0] ch_c_level_x;

    // Added init value to channel period combinatorial signals to keep
    // simulation from complaining about metavalues at 0ps.

    // Register-name signals.
    logic [11:0] ch_a_period_s = 12'h0;
    logic        ch_a_tone_en_n_s;
    logic        ch_a_noise_en_n_s;
    logic        ch_a_mode_s;

    logic [11:0] ch_b_period_s = 12'h0;
    logic        ch_b_tone_en_n_s;
    logic        ch_b_noise_en_n_s;
    logic        ch_b_mode_s;

    logic [11:0] ch_c_period_s = 12'h0;
    logic        ch_c_tone_en_n_s;
    logic        ch_c_noise_en_n_s;
    logic        ch_c_mode_s;

    logic [4:0]  noise_period_s = 5'h0;

    logic [15:0] env_period_s;
    logic        env_continue_s;
    logic        env_attack_s;
    logic        env_alternate_s;
    logic        env_hold_s;

    // Clock conditioning counters and enables.
    logic [2:0]  clk_div8_r = 3'b000;
    logic [2:0]  clk_div8_x;
    logic        en_cnt_r = 1'b0;
    logic        en_cnt_x;

    // Channel tone and noise counters.
    logic [11:0] ch_a_cnt_r = 12'h0;
    logic [11:0] ch_a_cnt_x;
    logic        flatline_a_s;
    logic        tone_a_r = 1'b1;
    logic        tone_a_x;

    logic [11:0] ch_b_cnt_r = 12'h0;
    logic [11:0] ch_b_cnt_x;
    logic        flatline_b_s;
    logic        tone_b_r = 1'b1;
    logic        tone_b_x;

    logic [11:0] ch_c_cnt_r = 12'h0;
    logic [11:0] ch_c_cnt_x;
    logic        flatline_c_s;
    logic        tone_c_r = 1'b1;
    logic        tone_c_x;

    logic [4:0]  noise_cnt_r = 5'h0;
    logic [4:0]  noise_cnt_x;
    logic        flatline_n_s;
    logic        noise_ff_r = 1'b1;
    logic        noise_ff_x;

    // 17-bit Noise LFSR.
    logic [16:0] noise_lfsr_r = 17'b1_0000_0000_0000_0000;
    logic [16:0] noise_lfsr_x;
    logic        noise_fb_s;
    logic        noise_s;

    // Tone and noise mixer.
    logic        mix_a_s;
    logic        mix_b_s;
    logic        mix_c_s;

    // Envelope counter.
    logic        env_shape_wr_r = 1'b0;
    logic        env_shape_wr_x;
    logic        env_rst_s;
    logic [15:0] env_cnt_r = 16'h0;
    logic [15:0] env_cnt_x;
    logic        env_ff_r = 1'b1;
    logic        env_ff_x;

    logic [4:0]  shape_cnt_r = 5'h0;
    logic [4:0]  shape_cnt_x;

    logic        continue_ff_r = 1'b1;
    logic        continue_ff_x;
    logic        attack_ff_r = 1'b0;
    logic        attack_ff_x;
    logic        hold_ff_r = 1'b0;
    logic        hold_ff_x;

    // Added init value to env_out_s to keep simulation from complaining
    // about metavalues at 0ps.
    logic        env_sel_s;
    logic [4:0]  env_out_s = 5'h0;

    // Amplitude control.
    logic [11:0] level_a_s;
    logic [11:0] level_b_s;
    logic [11:0] level_c_s;

    // DAC.
    logic [11:0] dac_a_r = 12'h0;
    logic [11:0] dac_b_r = 12'h0;
    logic [11:0] dac_c_r = 12'h0;
    logic [13:0] sum_audio_r = 14'h0;

    // Digital to Analogue Output-level lookup table ROM.
    //
    // The DAC is implemented with tuned NMOS transistors in the real IC.  For
    // the FPGA version, the 4-bit register level or 5-bit output from the
    // envelop is used as an index into a calculated table of values that
    // represent the equivalent voltage.
    //
    // The output scale is amplitude logarithmic.
    //
    // ln10 = Natural logarithm of 10, ~= 2.302585
    // amp  = Amplitude in voltage, 0.2, 1.45, etc.
    // dB   = decibel value in dB, -1.5, -3, etc.
    //
    // dB  = 20 * log(amp) / ln10
    // amp = 10 ^ (dB / 20)
    //
    // -1.5dB = 0.8413951416
    // -2.0dB = 0.7943282347
    // -3.0dB = 0.7079457843
    //
    // The datasheet defines a normalize 0V to 1V graph and oscilloscope photo
    // of the output curve.  The AY-3-8910 has 16-steps that are -3.0dB apart,
    // and the YM-2149 has 32-steps that are -1.5dB apart.
    //
    // 1V reference values based on the datasheet:
    //
    // 1.0000, 0.8414, 0.7079, 0.5957, 0.5012, 0.4217, 0.3548, 0.2985,
    // 0.2512, 0.2113, 0.1778, 0.1496, 0.1259, 0.1059, 0.0891, 0.0750,
    // 0.0631, 0.0531, 0.0447, 0.0376, 0.0316, 0.0266, 0.0224, 0.0188,
    // 0.0158, 0.0133, 0.0112, 0.0094, 0.0079, 0.0067, 0.0056, 0.0047
    //
    // A 10-bit number (0..1023) can support a scaled version of the reference
    // list without having any repeating values.  Using 9-bits is close, and
    // 8-bit values have too many duplicate values at the bottom-end to make for
    // a nice curve.  Duplicate values means several volume levels produce the
    // same output level, and is not accurate.
    //
    // Using a 12-bit output value means the three channels can be summed into a
    // 14-bit value without overflow, and leaves room for adjustments if
    // converting to something like 16-bit PCM.  The 12-bit values also provide
    // a nicer curve, and are easier to initialize in VHDL.
    //
    // The lowest volume level needs to go to 0 in a digital SoC to prevent
    // noise that would be filtered in a real system with external electronics.

    // Added init value to dac_reg_bit0_s to keep simulation from complaining
    // about metavalues at 0ps.
    logic        dac_reg_bit0_s = 1'b0;
    logic [11:0] dac_reg_level_s;
    logic [11:0] dac_env_level_s;

    // Output-level lookup table ROM.
    logic [11:0] dacrom_ar [0:31];

    initial begin
        //   19,  23,  27,  33,  39,  46,  55,  65,
        //   77,  92, 109, 129, 154, 183, 217, 258,
        //  307, 365, 434, 516, 613, 728, 865,1029,
        // 1223,1453,1727,2052,2439,2899,3446,4095
        dacrom_ar[0]  = 12'h000; dacrom_ar[1]  = 12'h017; dacrom_ar[2]  = 12'h01B; dacrom_ar[3]  = 12'h021;
        dacrom_ar[4]  = 12'h027; dacrom_ar[5]  = 12'h02E; dacrom_ar[6]  = 12'h037; dacrom_ar[7]  = 12'h041;
        dacrom_ar[8]  = 12'h04D; dacrom_ar[9]  = 12'h05C; dacrom_ar[10] = 12'h06D; dacrom_ar[11] = 12'h081;
        dacrom_ar[12] = 12'h09A; dacrom_ar[13] = 12'h0B7; dacrom_ar[14] = 12'h0D9; dacrom_ar[15] = 12'h102;
        dacrom_ar[16] = 12'h133; dacrom_ar[17] = 12'h16D; dacrom_ar[18] = 12'h1B2; dacrom_ar[19] = 12'h204;
        dacrom_ar[20] = 12'h265; dacrom_ar[21] = 12'h2D8; dacrom_ar[22] = 12'h361; dacrom_ar[23] = 12'h405;
        dacrom_ar[24] = 12'h4C7; dacrom_ar[25] = 12'h5AD; dacrom_ar[26] = 12'h6BF; dacrom_ar[27] = 12'h804;
        dacrom_ar[28] = 12'h987; dacrom_ar[29] = 12'hB53; dacrom_ar[30] = 12'hD76; dacrom_ar[31] = 12'hFFF;
    end

    // PCM signed 14-bit.
    logic [11:0] sign_a_r = 12'h0;
    logic [11:0] sign_a_x;
    logic [11:0] level_a_env_s;
    logic [11:0] sign_b_r = 12'h0;
    logic [11:0] sign_b_x;
    logic [11:0] level_b_env_s;
    logic [11:0] sign_c_r = 12'h0;
    logic [11:0] sign_c_x;
    logic [11:0] level_c_env_s;

    logic [13:0] pcm14s_r = 14'h0;


    // Register the input data at the full clock rate.
    always_ff @(posedge clk_i) begin
        sel_n_r  <= sel_n_i;
        busctl_r <= {bdir_i, bc_i};
        data_i_r <= data_i;
    end

    // Registered data output.
    assign data_r_o = data_o_r;


    // -----------------------------------------------------------------------
    //
    // External bus interface and register file.
    //
    // BDIR BC  State
    //  0   0   Inactive
    //  0   1   Read from PSG register
    //  1   0   Write to PSG register
    //  1   1   Latch address
    //
    // A generic register file is used here instead of specific registers and
    // decode logic.  However, the real IC only has registers of exact size and
    // performs decode and generates enable signals.
    //

    always_comb begin
        reg_addr_x   = reg_addr_r;
        en_data_rd_s = 1'b0;
        en_data_wr_s = 1'b0;

        case (busctl_r)
            2'b00: begin // inactive.
                // null
            end
            2'b01: begin // read from PSG register.
                en_data_rd_s = 1'b1;
            end
            2'b10: begin // write to PSG register.
                en_data_wr_s = 1'b1;
            end
            // 2'b11
            default: begin // latch register address.
                // The PSG is factory set to a high-address mask of "0000", unless the
                // PSG was special ordered with a custom-masked address.
                if (data_i_r[7:4] == ADDRESS_G)
                    reg_addr_x = data_i_r[3:0];
            end
        endcase
    end

    // Decode envelope shape register writes since they cause a reset of the
    // envelope counter and state machine.  The enable lasts as long as the
    // write cycle, which is accurate to the real IC.  It is registered to
    // prevent long combinatorial paths from the write enable.
    assign env_shape_wr_x = (reg_addr_r == 4'hD) ? en_data_wr_s : 1'b0;


    // The output-level is converted to the equivalent DAC value and stored as
    // as the look-up result, rather than the 4-bit level index.  This allows
    // sharing of the ROM lookup table, and uses less FPGA resources.

    always_ff @(posedge clk_i) begin
        if (!reset_n_i)
           dac_reg_bit0_s <= 1'b0;
        else
            dac_reg_bit0_s  <= (data_i_r[3:0] == 4'b0000) ? 1'b0 : 1'b1;
    end

    assign dac_reg_level_s = dacrom_ar[{data_i_r[3:0], dac_reg_bit0_s}];

    assign ch_a_level_x = (reg_addr_r == 4'h8) ? dac_reg_level_s : ch_a_level_r;
    assign ch_b_level_x = (reg_addr_r == 4'h9) ? dac_reg_level_s : ch_b_level_r;
    assign ch_c_level_x = (reg_addr_r == 4'hA) ? dac_reg_level_s : ch_c_level_r;


    // Registers.
    //
    //     7654 3210
    // R0  PPPP PPPP  Channel A tone period  7..0.
    // R1  ---- PPPP  Channel A tone period 11..8.
    // R2  PPPP PPPP  Channel B tone period  7..0.
    // R3  ---- PPPP  Channel B tone period 11..8.
    // R4  PPPP PPPP  Channel C tone period  7..0.
    // R5  ---- PPPP  Channel C tone period 11..8.
    // R6  ---P PPPP  Noise shift period.
    // R7  I--- ----  I/O Port B IN_n/OUT control.
    //     -I-- ----  I/O Port A IN_n/OUT control.
    //     --C- ----  Mix Noise with Channel C, active low.
    //     ---B ----  Mix Noise with Channel B, active low.
    //     ---- A---  Mix Noise with Channel A, active low.
    //     ---- -C--  Enable Channel C, active low.
    //     ---- --B-  Enable Channel B, active low.
    //     ---- ---A  Enable Channel A, active low.
    // R8  ---M ----  Channel A Mode, 0=level, 1=envelope.
    //     ---- LLLL  Channel A Level.
    // R9  ---M ----  Channel B Mode, 0=level, 1=envelope.
    //     ---- LLLL  Channel B Level.
    // R10 ---M ----  Channel C Mode, 0=level, 1=envelope.
    //     ---- LLLL  Channel C Level.
    // R11 PPPP PPPP  Envelope period  7..0.
    // R12 PPPP PPPP  Envelope period 15..8.
    // R13 ---- C---  Envelope shape "Continue" control.
    //     ---- -A--  Envelope shape "Attack" control.
    //     ---- --A-  Envelope shape "Alternate" control.
    //     ---- ---H  Envelope shape "Hole" control.
    // R14 DDDD DDDD  I/O port A data.
    // R15 DDDD DDDD  I/O port B data.

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            reg_addr_r      <= 4'h0;
            data_o_r        <= 8'h0;
            env_shape_wr_r  <= 1'b0;
            ch_a_level_r    <= 12'h800; // Default to half-range for 0 level.
            ch_b_level_r    <= 12'h800; // Default to half-range for 0 level.
            ch_c_level_r    <= 12'h800; // Default to half-range for 0 level.

            reg_file_ar[0]  <= 8'h00;
            reg_file_ar[1]  <= 8'h00;
            reg_file_ar[2]  <= 8'h00;
            reg_file_ar[3]  <= 8'h00;
            reg_file_ar[4]  <= 8'h00;
            reg_file_ar[5]  <= 8'h00;
            reg_file_ar[6]  <= 8'h00;
            reg_file_ar[7]  <= 8'h00;
            reg_file_ar[8]  <= 8'h00;
            reg_file_ar[9]  <= 8'h00;
            reg_file_ar[10] <= 8'h00;
            reg_file_ar[11] <= 8'h00;
            reg_file_ar[12] <= 8'h00;
            reg_file_ar[13] <= 8'h00;
            reg_file_ar[14] <= 8'h00;
            reg_file_ar[15] <= 8'h00;

        end else if (en_clk_psg_i) begin
            reg_addr_r     <= reg_addr_x;
            env_shape_wr_r <= env_shape_wr_x;

            if (en_data_rd_s) begin
                data_o_r <= reg_file_ar[reg_addr_r];
            end else if (en_data_wr_s) begin
                reg_file_ar[reg_addr_r] <= data_i_r;

                ch_a_level_r <= ch_a_level_x;
                ch_b_level_r <= ch_b_level_x;
                ch_c_level_r <= ch_c_level_x;
            end
        end
    end


    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            ch_a_period_s   <= 12'h000;
            ch_b_period_s   <= 12'h000;
            ch_c_period_s   <= 12'h000;
            noise_period_s  <= 5'h0;
        end else begin
            ch_a_period_s   <= {reg_file_ar[1][3:0], reg_file_ar[0]};
            ch_b_period_s   <= {reg_file_ar[3][3:0], reg_file_ar[2]};
            ch_c_period_s   <= {reg_file_ar[5][3:0], reg_file_ar[4]};
            noise_period_s  <= reg_file_ar[6][4:0];
        end
    end

    // Register file name mapping.  Convenience for this implementation.  The
    // real IC does not have full 16x8-bit registers.  Confirmed via die-shots.
    // assign ch_a_period_s     = {reg_file_ar[1][3:0], reg_file_ar[0]};
    assign ch_a_tone_en_n_s  = reg_file_ar[7][0];
    assign ch_a_noise_en_n_s = reg_file_ar[7][3];
    assign ch_a_mode_s       = reg_file_ar[8][4];

    // assign ch_b_period_s     = {reg_file_ar[3][3:0], reg_file_ar[2]};
    assign ch_b_tone_en_n_s  = reg_file_ar[7][1];
    assign ch_b_noise_en_n_s = reg_file_ar[7][4];
    assign ch_b_mode_s       = reg_file_ar[9][4];

    // assign ch_c_period_s     = {reg_file_ar[5][3:0], reg_file_ar[4]};
    assign ch_c_tone_en_n_s  = reg_file_ar[7][2];
    assign ch_c_noise_en_n_s = reg_file_ar[7][5];
    assign ch_c_mode_s       = reg_file_ar[10][4];

    // assign noise_period_s    = reg_file_ar[6][4:0];

    assign env_period_s      = {reg_file_ar[12], reg_file_ar[11]};
    assign env_continue_s    = reg_file_ar[13][3];
    assign env_attack_s      = reg_file_ar[13][2];
    assign env_alternate_s   = reg_file_ar[13][1];
    assign env_hold_s        = reg_file_ar[13][0];

    // TODO implement I/O registers.


    // -----------------------------------------------------------------------
    //
    // Clock conditioning.
    //

    // Divide the input clock enable.
    assign sel_ff_x = ~sel_ff_r;

    // Select the clock enable based on the sel_n_i input.
    assign en_int_clk_psg_s = (!sel_n_r) ? (en_clk_psg_i & sel_ff_r) : en_clk_psg_i;

    always_ff @(posedge clk_i) begin
        if (en_clk_psg_i)
            sel_ff_r <= sel_ff_x;
    end


    // Reduce the input clock to provide the divide by eight clock-phases, count
    // enable, and count reset.
    assign clk_div8_x = clk_div8_r + 1'b1;

    // The real IC counts on the 4th divider count (100), so do the same with
    // the enable (which is active during the next state, thus 3 instead of 4).
    assign en_cnt_x = (clk_div8_r == 3'd3) ? 1'b1 : 1'b0;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            clk_div8_r <= 3'b000;
            en_cnt_r   <= 1'b0;
        end else if (en_int_clk_psg_s) begin
            clk_div8_r <= clk_div8_x;
            en_cnt_r   <= en_cnt_x;
        end
    end


    // -----------------------------------------------------------------------
    //
    // Channel tone counters.  The counters *always* count unless in reset.
    //

    // Timing for 0 and 1 period-count, showing why they are the same.  The real
    // IC counts on the 4-count of the clock divider, so this implementation
    // does the same.  In the real IC, the >= reset and count enable happen in
    // the same 4-count cycle due to the asynchronous nature of the IC.  In a
    // synchronous FPGA design, the >= reset is performed 1-cycle prior to the
    // count enable.
    //   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _
    // _/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_ PSG clock (input clock enable)
    //           _______________                 _______________
    // ___3___4_/ 5   6   7   0 \_1___2___3___4_/ 5   6   7   0 \_1___2___3___4_ divided clock count
    //   ___                             ___                             ___
    // _/   \___________________________/   \___________________________/   \___ >= enable (resets count to 0)
    //       ___                             ___                             ___
    // _____/   \___________________________/   \___________________________/    count enable
    // _____ ___ ___________________________ ___ ___________________________ ___
    // _____X_0_X______________1____________X_0_X______________1____________X_0_ tone counter
    // _____                                 _______________________________
    //      \_______________________________/                               \___ tone flip-flop

    // The tone counter >= reset strobe must be enabled prior to the count enable
    // so the tone counter is only a zero-count for *one input clock cycle*, and
    // not the count-enable cycle (i.e. input clock divided by 8).
    //
    // This is the reason why a period-count of zero is the same as a period-
    // count of one.  The time the counter has a zero value is merged with the
    // last 8-cycle period where the >= condition is detected.
    //
    // In the real IC the reset is asynchronous combinatorial logic (as is the
    // whole IC).  For the FPGA, combinatorial look-ahead is used.
    //
    // The channel counters in the real IC perform a greater-than or equal-to
    // comparison to toggle the tone output flip-flop.
    //
    // Loading new values into the registers does NOT affect the counter or tone
    // flip-flop in any way directly.  A new register value many cause the >=
    // comparison be become true immediately, which will cause the tone flip-
    // flop to *toggle*, but does not guarantee the high or low state of the
    // flip-flop.
    //
    // The *only* way to set the tone flip-flop to a known state is via the
    // external chip reset, in which case the flip-flop will be set ('1').
    //
    // A chip-accurate counter implementation in C might look like this:
    //
    // {
    //   if ( counter >= period ) {
    //     tone = !tone;
    //     counter = 0;
    //   }
    //
    //   counter++;
    // }
    //
    // With the period work-around described below:
    //
    // {
    //   if ( counter >= period )
    //   {
    //     if ( period < 6 ) {
    //       tone = 1;
    //     } else {
    //       tone = !tone;
    //     }
    //
    //     counter = 0;
    //   }
    //
    //   counter++;
    // }

    // High frequency noise problem.
    //
    // With a typical 1.78MHz input clock, the divide by eight produces a
    // 223.72KHz clock into the tone counters.  With small period counts,
    // frequencies *well over* the human hearing range can be produced.
    //
    // The problem with the frequencies over 20KHz is, in a digital SoC the high
    // frequencies do not filter out like they do when the output is connected
    // to an external low-pass filter and inductive load (speaker), like they
    // are with the real IC.
    //
    // In an all digital system with digital audio, the generated frequencies
    // should never be more than the Nyquist frequency (twice the sample rate).
    // Typical sample rates are 44KHz or 48KHz, so any frequency over 20KHz
    // should not be output (and is not audible to a human anyway).
    //
    // The work-around here is to flat-line the toggle flip-flop for any tone
    // counter with a period that produces a frequency over the Nyquist rate.
    // This change still allows the technique of modulating the output with
    // rapid volume level changes.
    //
    // Based on a typical PSG clock of 1.78MHz for a Z80-based system, the
    // period counts that cause frequencies above 20KHz are:
    //
    // f = CLK / (16 * Count)
    //
    // Clock 1,789,772Hz  55.873ns
    //
    // Count  Frequency     Period
    //   0   111860.78Hz   8.9396us  * same as a count of 1, see above.
    //   1   111860.78Hz   8.9396us
    //   2    55930.39Hz  17.8793us
    //   3    37286.92Hz  26.8190us
    //   4    27965.19Hz  35.7587us
    //   5    22372.15Hz  44.6984us
    // ----------------------------
    //   6    18643.46Hz  53.6381us  First audible count.


    // A channel counter and tone flip-flop.
    assign ch_a_cnt_x =
        // Reset uses counter next-state look-ahead.
        (en_cnt_x && ch_a_cnt_r >= ch_a_period_s) ? 12'h0 :
        // Counting uses current-state.
        (en_cnt_r) ? ch_a_cnt_r + 1'b1 :
        ch_a_cnt_r;

    assign flatline_a_s = (ch_a_period_s < 12'd6) ? 1'b1 : 1'b0;

    assign tone_a_x =
        // Flat-line the output for counts that produce frequencies > 20KHz.
        (flatline_a_s) ? 1'b1 :
        // Toggle uses counter next-state look-ahead, same condition as reset.
        (en_cnt_x && ch_a_cnt_r >= ch_a_period_s) ? ~tone_a_r :
        tone_a_r;

    // B channel counter and tone flip-flop.
    assign ch_b_cnt_x =
        (en_cnt_x && ch_b_cnt_r >= ch_b_period_s) ? 12'h0 :
        (en_cnt_r) ? ch_b_cnt_r + 1'b1 :
        ch_b_cnt_r;

    assign flatline_b_s = (ch_b_period_s < 12'd6) ? 1'b1 : 1'b0;

    assign tone_b_x =
        (flatline_b_s) ? 1'b1 :
        (en_cnt_x && ch_b_cnt_r >= ch_b_period_s) ? ~tone_b_r :
        tone_b_r;

    // C channel counter and tone flip-flop.
    assign ch_c_cnt_x =
        (en_cnt_x && ch_c_cnt_r >= ch_c_period_s) ? 12'h0 :
        (en_cnt_r) ? ch_c_cnt_r + 1'b1 :
        ch_c_cnt_r;

    assign flatline_c_s = (ch_c_period_s < 12'd6) ? 1'b1 : 1'b0;

    assign tone_c_x =
        (flatline_c_s) ? 1'b1 :
        (en_cnt_x && ch_c_cnt_r >= ch_c_period_s) ? ~tone_c_r :
        tone_c_r;


    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            ch_a_cnt_r <= 12'h0;
            tone_a_r   <= 1'b1; // Verified resets to '1' in the real IC.

            ch_b_cnt_r <= 12'h0;
            tone_b_r   <= 1'b1; // Verified resets to '1' in the real IC.

            ch_c_cnt_r <= 12'h0;
            tone_c_r   <= 1'b1; // Verified resets to '1' in the real IC.

        end else if (en_int_clk_psg_s) begin
            ch_a_cnt_r <= ch_a_cnt_x;
            tone_a_r   <= tone_a_x;

            ch_b_cnt_r <= ch_b_cnt_x;
            tone_b_r   <= tone_b_x;

            ch_c_cnt_r <= ch_c_cnt_x;
            tone_c_r   <= tone_c_x;
        end
    end


    // -----------------------------------------------------------------------
    //
    // Noise period counter.  Identical to the tone counters, only shorter, and
    // the toggle flip-flop output of the counter is used as the clock input to
    // the LFSR.  Thus, the noise counter effectively divides the output shift
    // rate in half one additional time.
    //
    // With the lowest period counter of 0 or 1 (both values produce the same
    // count), the LFSR will output a bit at the rate of one-bit for every 16
    // main clock cycles, maximum.
    //
    // The noise counter has the same high frequency problem for digital systems
    // as the tone counters, but the noise counter has one extra flip-flop
    // before the counter, so its minimum counter will be one lower than the
    // tone counter minimum.
    //
    // PSG
    // Clk   3,579,545Hz   2.793651ns
    //
    // Cnt   Frequency       Period
    //  0   55930.39062Hz  17.87936us  * same as a count of 1, see above.
    //  1   55930.39062Hz  17.87936us
    //  2   37286.92708Hz  26.81905us
    //  3   27965.19531Hz  35.75873us
    //  4   22372.15625Hz  44.69841us
    // -------------------------------
    //  5   18643.46354Hz  53.63810us  First audible count.

    assign noise_cnt_x =
        // Reset uses counter next-state look-ahead.
        (en_cnt_x && noise_cnt_r >= noise_period_s) ? 5'h0 :
        // Counting uses current-state.
        (en_cnt_r) ? noise_cnt_r + 1'b1 :
        noise_cnt_r;

    assign flatline_n_s = (noise_period_s < 5'd5) ? 1'b1 : 1'b0;

    assign noise_ff_x =
        // Flat-line the output for counts that produce frequencies > 20KHz.
        (flatline_n_s) ? 1'b1 :
        // Toggle uses counter next-state look-ahead, same condition as reset.
        (en_cnt_x && noise_cnt_r >= noise_period_s) ? ~noise_ff_r :
        noise_ff_r;


    // Noise 17-bit right-shift LFSR with taps at 0 and 3, LS-bit is the output.
    // Verified against the reverse engineered 8910 die-shot.  Reset loads the
    // LFSR with 0x10000 to prevent lock-up.
    assign noise_fb_s   = noise_lfsr_r[3] ^ noise_lfsr_r[0];
    assign noise_lfsr_x = {noise_fb_s, noise_lfsr_r[16:1]};
    assign noise_s      = noise_lfsr_r[0];


    always_ff @(posedge clk_i) begin
        if (!reset_n_i) begin
            noise_cnt_r  <= 5'h0;
            noise_ff_r   <= 1'b1; // Verified resets to '1' in the real IC.
            noise_lfsr_r <= 17'b1_0000_0000_0000_0000;

        end else if (en_int_clk_psg_s) begin
            noise_cnt_r <= noise_cnt_x;
            noise_ff_r  <= noise_ff_x;
            // Look-ahead rising-edge detect the noise flip-flop.
            if (!noise_ff_r && noise_ff_x)
                noise_lfsr_r <= noise_lfsr_x;
        end
    end


    // -----------------------------------------------------------------------
    //
    // Tone and Noise mixer.
    //
    // The output of the tone and noise section is a '0' or '1' for each channel
    // and the noise.  Each tone bit is optionally mixed with the noise bit.
    // The final bit is used to determine if the amplitude is used or not.

    // Tone and noise mixer.  The enables are active low, so if the channel and
    // noise are disabled, the output will be a '1', not a '0'.  This allows a
    // disabled channel to still be amplitude modulated by changing the volume.

    assign mix_a_s = (ch_a_tone_en_n_s | tone_a_r) & (ch_a_noise_en_n_s | noise_s);
    assign mix_b_s = (ch_b_tone_en_n_s | tone_b_r) & (ch_b_noise_en_n_s | noise_s);
    assign mix_c_s = (ch_c_tone_en_n_s | tone_c_r) & (ch_c_noise_en_n_s | noise_s);


    // -----------------------------------------------------------------------
    //
    // Envelope counter.  Works the same as the noise counter, with the envelope
    // period-counter clocking the envelope shape-counter.  The YM-2149 has a
    // 5-bit shape counter, but it counts twice as fast so it produces smoother
    // ramping of the envelope in the same time (one cycle of the envelope
    // period).
    //
    // When the envelope-period is 0 or 1, the AY-3-8910 shape-counter counts at
    // one-count for every 16 main-clock cycles, and the YM-2149 counts twice in
    // the same 16 cycles.
    //
    // Unlike the other counters, the envelope period-counter, shape-counter,
    // and shape FSM are reset when the shape register is written, as well as
    // the global reset.

    assign env_cnt_x =
        // Reset uses counter next-state look-ahead.
        (en_cnt_x && env_cnt_r >= env_period_s) ? 16'h0 :
        // Counting uses current-state.
        (en_cnt_r) ? env_cnt_r + 1'b1 :
        env_cnt_r;

    assign env_ff_x =
        // Toggle uses counter next-state look-ahead, same condition as reset.
        (en_cnt_x && env_cnt_r >= env_period_s) ? ~env_ff_r :
        env_ff_r;

    // The envelope reset is active during the global reset input as well as
    // when the envelope shape register is written.
    assign env_rst_s = (~reset_n_i) | env_shape_wr_r;

    // Shape counter.  Hold forces the shape counter to a "set" state.
    // Look-ahead on the hold flip-flop to prevent counter roll-over.
    assign shape_cnt_x = (hold_ff_x) ? 5'h1F : shape_cnt_r + 1'b1;


    always_ff @(posedge clk_i) begin
        // ** NOTE: This reset is active high.
        if (env_rst_s) begin
            env_cnt_r   <= 16'h0;
            env_ff_r    <= 1'b1; // Verified resets to '1' in the real IC.
            shape_cnt_r <= 5'h0;

        end else if (en_int_clk_psg_s) begin
            env_cnt_r <= env_cnt_x;
            env_ff_r  <= env_ff_x;

            // Look-ahead edge detect the envelope flip-flop to provide two
            // counts in the same number of cycles.  Hold inhibits the shape
            // counter's clock input.
            if (!hold_ff_r && env_ff_r != env_ff_x)
                shape_cnt_r <= shape_cnt_x;
        end
    end


    // -----------------------------------------------------------------------
    //
    // Envelope FSM.  Four envelope control bits determine how the shape
    // counter operates after it has counted from 0 to 31.
    //
    // The envelope waveform is used as an amplitude control for use with the
    // tone channels.
    //
    // Register 15 Envelope Shape Control
    //
    //  +-------  Continue
    //  | +-----  Attack
    //  | | +---  Alternate
    //  | | | +-  Hold
    //  3 2 1 0
    //  -------
    //            \
    //  0 0 X X    \______________
    //
    //             /|
    //  0 1 X X   / |_____________
    //
    //            \ |\ |\ |\ |\ |\
    //  1 0 0 0    \| \| \| \| \| \
    //
    //            \
    //  1 0 0 1    \______________
    //
    //            \  /\  /\  /\  /
    //  1 0 1 0    \/  \/  \/  \/
    //               _____________
    //            \ |
    //  1 0 1 1    \|
    //
    //             /| /| /| /| /| /|
    //  1 1 0 0   / |/ |/ |/ |/ |/ |
    //              _______________
    //             /
    //  1 1 0 1   /
    //
    //             /\  /\  /\  /\
    //  1 1 1 0   /  \/  \/  \/  \
    //
    //             /|
    //  1 1 1 1   / |______________

    // Continue is rather useless, since the envelopes created by using it are
    // duplicates of envelopes created with the other three control bits.

    // "Continue" is a final envelope output select.  After the shape counter
    // completes the first 0..31 count after being reset, if the continue bit
    // from the shape register is zero, the final envelope output will be zero.
    assign continue_ff_x = (shape_cnt_r == 5'd31) ? env_continue_s : continue_ff_r;

    // "Attack" is a selection between the regular or inverted shape count.
    // The real IC gates the ~q output from the attack flip-flop when the
    // attack register is '1'.
    assign env_sel_s = (env_attack_s) ? ~attack_ff_r : attack_ff_r;

    // "Alternate" is an enable for toggling the Attack flip-flop.
    assign attack_ff_x =
        (shape_cnt_r == 5'd31 && env_alternate_s) ? ~attack_ff_r :
        attack_ff_r;

    // "Hold" sets ('1') all the flip-flops in the shape counter and inhibits it
    // it from counting.  The only way to reset the hold is the global reset or
    // writing to the shape register (which issues the local envelope reset).
    assign hold_ff_x = (shape_cnt_r == 5'd31) ? env_hold_s : hold_ff_r;

    // assign env_out_s =
    //     (!continue_ff_r) ? 5'h0 :
    //     (!env_sel_s)     ? ~shape_cnt_r :
    //     shape_cnt_r;

    always_ff @(posedge clk_i) begin
        if (!reset_n_i)
            env_out_s <= 5'h0;
        else
            env_out_s <=
                (!continue_ff_r) ? 5'h0 :
                (!env_sel_s)     ? ~shape_cnt_r :
                shape_cnt_r;
    end

    assign dac_env_level_s = dacrom_ar[env_out_s];

    always_ff @(posedge clk_i) begin
        // ** NOTE: This reset is active high.
        if (env_rst_s) begin
            continue_ff_r  <= 1'b1;
            attack_ff_r    <= 1'b0;
            hold_ff_r      <= 1'b0;

        end else if (en_int_clk_psg_s) begin
            // Look-ahead edge detect the envelope flip-flop to provide two
            // counts in the same number of cycles.  Hold inhibits the shape
            // counter's clock input.
            if (!hold_ff_r && env_ff_r != env_ff_x) begin
                continue_ff_r  <= continue_ff_x;
                attack_ff_r    <= attack_ff_x;
                hold_ff_r      <= hold_ff_x;
            end
        end
    end


    // -----------------------------------------------------------------------
    //
    // Amplitude control.  The amplitude of each tone channel is controlled
    // by one of two ways:
    //
    //   1. The 4-bit amplitude setting from the channel's amplitude register.
    //   2. The 5-bit amplitude from the envelope generator.
    //
    // The selection is controlled by a mode-bit in each channel's amplitude
    // register.
    //
    // Because the envelope amplitude is 5-bits vs the 4-bits of the amplitude
    // register, the envelope amplitude will produce smoother ramps by changing
    // the level in 1.5dB half steps.
    //
    // The output of the mixer takes precedence, otherwise the level vs.
    // envelope selection is used.


    assign level_a_s =
        (!mix_a_s)      ? 12'h0 :
        (!ch_a_mode_s)  ? ch_a_level_r :
        dac_env_level_s;

    assign level_b_s =
        (!mix_b_s)      ? 12'h0 :
        (!ch_b_mode_s)  ? ch_b_level_r :
        dac_env_level_s;

    assign level_c_s =
        (!mix_c_s)      ? 12'h0 :
        (!ch_c_mode_s)  ? ch_c_level_r :
        dac_env_level_s;


    // -----------------------------------------------------------------------
    //
    // Digital to Analogue Converter.
    //

    assign ch_a_o = dac_a_r;
    assign ch_b_o = dac_b_r;
    assign ch_c_o = dac_c_r;
    assign mix_audio_o = sum_audio_r;

    always_ff @(posedge clk_i) begin
        if (en_clk_psg_i) begin
            dac_a_r <= level_a_s;
            dac_b_r <= level_b_s;
            dac_c_r <= level_c_s;

            // Convenience sum the audio channels.
            sum_audio_r <= {2'b00, dac_a_r} + {2'b00, dac_b_r} + {2'b00, dac_c_r};
        end
    end


    // -----------------------------------------------------------------------
    //
    // Signed zero-centered 14-bit PCM.
    //

    // Make a -/+ level value depending on the tone state.  When the tone is
    // disabled, adjust the unsigned level-range to a signed-level range.
    //
    // signed_level =
    //    level - (range / 2) when disabled
    //  -(level / 2)          when tone == 0
    //   (level / 2)          when tone == 1

    assign level_a_env_s = (!ch_a_mode_s) ? ch_a_level_r : dac_env_level_s;
    assign level_b_env_s = (!ch_b_mode_s) ? ch_b_level_r : dac_env_level_s;
    assign level_c_env_s = (!ch_c_mode_s) ? ch_c_level_r : dac_env_level_s;

    assign sign_a_x =
        // Make a flat-level into a full-range signed value.
        ((ch_a_tone_en_n_s & ch_a_noise_en_n_s) |
         flatline_a_s |
         ((~ch_a_noise_en_n_s) & flatline_n_s)) ? level_a_env_s - 12'h800 :
        // Otherwise, make signed range value from tone 0 or 1.
        (!mix_a_s) ? ({1'b1, ~level_a_env_s[11:1]} + 1'b1) :
        {1'b0, level_a_env_s[11:1]};

    assign sign_b_x =
        ((ch_b_tone_en_n_s & ch_b_noise_en_n_s) |
         flatline_b_s |
         ((~ch_b_noise_en_n_s) & flatline_n_s)) ? level_b_env_s - 12'h800 :
        (!mix_b_s) ? ({1'b1, ~level_b_env_s[11:1]} + 1'b1) :
        {1'b0, level_b_env_s[11:1]};

    assign sign_c_x =
        ((ch_c_tone_en_n_s & ch_c_noise_en_n_s) |
         flatline_c_s |
         ((~ch_c_noise_en_n_s) & flatline_n_s)) ? level_c_env_s - 12'h800 :
        (!mix_c_s) ? ({1'b1, ~level_c_env_s[11:1]} + 1'b1) :
        {1'b0, level_c_env_s[11:1]};


    assign pcm14s_o = pcm14s_r;


    always_ff @(posedge clk_i) begin
        if (en_clk_psg_i) begin
            sign_a_r <= sign_a_x;
            sign_b_r <= sign_b_x;
            sign_c_r <= sign_c_x;

            // Sum to signed 14-bit.
            pcm14s_r <=
                {{2{sign_a_r[11]}}, sign_a_r} +
                {{2{sign_b_r[11]}}, sign_b_r} +
                {{2{sign_c_r[11]}}, sign_c_r};
        end
    end

endmodule
