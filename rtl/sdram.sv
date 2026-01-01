//   __   __     __  __     __         __
//  /\ "-./\ \   /\ \/\ \   /\ \       /\ \
//  \ \ \-./\ \  \ \ \_\ \  \ \ \____  \ \ \____
//   \ \_\ \ \_\  \ \_____\  \ \_____\  \ \_____\
//    \/_/  \/_/   \/_____/   \/_____/   \/_____/
//   ______     ______       __     ______     ______     ______
//  /\  __ \   /\  == \     /\ \   /\  ___\   /\  ___\   /\__  _\
//  \ \ \/\ \  \ \  __<    _\_\ \  \ \  __\   \ \ \____  \/_/\ \/
//   \ \_____\  \ \_____\ /\_____\  \ \_____\  \ \_____\    \ \_\
//    \/_____/   \/_____/ \/_____/   \/_____/   \/_____/     \/_/
//
// https://joshbassett.info
// https://twitter.com/nullobject
// https://github.com/nullobject
//
//
// Copyright (c) 2020 Josh Bassett
// Converted to SystemVerilog and modified by (c) 2025 Ryan "rj45" Sanche
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// This SDRAM controller provides a symmetric 32-bit synchronous read/write
// interface for a 16Mx16-bit SDRAM chip (e.g. AS4C16M16SA-6TCN, IS42S16400F,
// etc.).

`default_nettype none
`timescale 1ns / 1ps

module sdram #(
    // clock frequency (in MHz)
    //
    // This value must be provided, as it is used to calculate the number of
    // clock cycles required for the other timing values.
    parameter real CLK_FREQ = 60.0,

    // 32-bit controller interface
    parameter ADDR_WIDTH = 23,
    parameter DATA_WIDTH = 32,

    // SDRAM interface
    parameter SDRAM_ADDR_WIDTH = 13,
    parameter SDRAM_DATA_WIDTH = 16,
    parameter SDRAM_COL_WIDTH  = 9,
    parameter SDRAM_ROW_WIDTH  = 13,
    parameter SDRAM_BANK_WIDTH = 2,

    // The delay in clock cycles, between the start of a read command and the
    // availability of the output data.
    parameter CAS_LATENCY = 2, // 2=below 133MHz, 3=above 133MHz

    // The number of 16-bit words to be bursted during a read/write.
    parameter BURST_LENGTH = 2,

    // timing values (in nanoseconds)
    //
    // These values can be adjusted to match the exact timing of your SDRAM
    // chip (refer to the datasheet).
    parameter real T_DESL = 200000.0, // startup delay
    parameter real T_MRD  =     14.0, // mode register cycle time
    parameter real T_RC   =     60.0, // row cycle time
    parameter real T_RCD  =     15.0, // RAS to CAS delay
    parameter real T_RP   =     15.0, // precharge to activate delay
    parameter real T_WR   =     12.0, // write recovery time
    parameter real T_REFI =   7800.0  // average refresh interval
) (
    // reset
    input  logic                      reset,

    // clock
    input  logic                      clk,

    // address bus
    input  logic [ADDR_WIDTH-1:0]     addr,

    // input data bus
    input  logic [DATA_WIDTH-1:0]     data,

    // When the write enable signal is asserted, a write operation will be performed.
    input  logic                      we,

    // When the request signal is asserted, an operation will be performed.
    input  logic                      req,

    // The acknowledge signal is asserted by the SDRAM controller when
    // a request has been accepted.
    output logic                      ack,

    // The valid signal is asserted when there is a valid word on the output
    // data bus.
    output logic                      valid,

    // output data bus
    output logic [DATA_WIDTH-1:0]     q,

    // SDRAM interface (e.g. AS4C16M16SA-6TCN, IS42S16400F, etc.)
    output logic [SDRAM_ADDR_WIDTH-1:0] sdram_a,
    output logic [SDRAM_BANK_WIDTH-1:0] sdram_ba,
    inout  wire  [SDRAM_DATA_WIDTH-1:0] sdram_dq,
    output logic                        sdram_cke,
    output logic                        sdram_cs_n,
    output logic                        sdram_ras_n,
    output logic                        sdram_cas_n,
    output logic                        sdram_we_n,
    output logic                        sdram_dqml,
    output logic                        sdram_dqmh
);

    // commands
    localparam logic [3:0] CMD_DESELECT     = 4'b1111;
    localparam logic [3:0] CMD_LOAD_MODE    = 4'b0000;
    localparam logic [3:0] CMD_AUTO_REFRESH = 4'b0001;
    localparam logic [3:0] CMD_PRECHARGE    = 4'b0010;
    localparam logic [3:0] CMD_ACTIVE       = 4'b0011;
    localparam logic [3:0] CMD_WRITE        = 4'b0100;
    localparam logic [3:0] CMD_READ         = 4'b0101;
    localparam logic [3:0] CMD_NOP          = 4'b0111;

    // the ordering of the accesses within a burst
    localparam logic BURST_TYPE = 1'b0; // 0=sequential, 1=interleaved

    // the write burst mode enables bursting for write operations
    localparam logic WRITE_BURST_MODE = 1'b0; // 0=burst, 1=single

    // the value written to the mode register to configure the memory
    localparam logic [SDRAM_ADDR_WIDTH-1:0] MODE_REG = {
        3'b000,
        WRITE_BURST_MODE,
        2'b00,
        3'(CAS_LATENCY),
        BURST_TYPE,
        3'($clog2(BURST_LENGTH))
    };

    // calculate the clock period (in nanoseconds)
    localparam real CLK_PERIOD = 1.0 / CLK_FREQ * 1000.0;

    // verilator lint_off WIDTHTRUNC

    // the number of clock cycles to wait before initialising the device
    localparam logic [13:0] INIT_WAIT = $rtoi($ceil(T_DESL / CLK_PERIOD));

    // the number of clock cycles to wait while a LOAD MODE command is being
    // executed
    localparam logic [13:0] LOAD_MODE_WAIT = $rtoi($ceil(T_MRD / CLK_PERIOD));

    // the number of clock cycles to wait while an ACTIVE command is being
    // executed
    localparam logic [13:0] ACTIVE_WAIT = $rtoi($ceil(T_RCD / CLK_PERIOD));

    // the number of clock cycles to wait while a REFRESH command is being
    // executed
    localparam logic [13:0] REFRESH_WAIT = $rtoi($ceil(T_RC / CLK_PERIOD));

    // the number of clock cycles to wait while a PRECHARGE command is being
    // executed
    localparam logic [13:0] PRECHARGE_WAIT = $rtoi($ceil(T_RP / CLK_PERIOD));

    // the number of clock cycles to wait while a READ command is being executed
    localparam logic [13:0] READ_WAIT = CAS_LATENCY + BURST_LENGTH;

    // the number of clock cycles to wait while a WRITE command is being executed
    localparam logic [13:0] WRITE_WAIT = BURST_LENGTH + $rtoi($ceil((T_WR + T_RP) / CLK_PERIOD));

    // the number of clock cycles before the memory controller needs to refresh
    // the SDRAM
    localparam logic [9:0] REFRESH_INTERVAL = $rtoi($floor(T_REFI / CLK_PERIOD)) - 10;

    // verilator lint_on WIDTHTRUNC

    typedef enum logic [2:0] {
        INIT,
        MODE,
        IDLE,
        ACTIVE,
        READ,
        WRITE,
        REFRESH
    } state_t;

    // state signals
    state_t state, next_state;

    // command signals
    logic [3:0] cmd, next_cmd;

    // control signals
    logic start;
    logic load_mode_done;
    logic active_done;
    logic refresh_done;
    logic first_word;
    logic read_done;
    logic write_done;
    logic should_refresh;

    // counters
    logic [13:0] wait_counter;
    logic [9:0]  refresh_counter;

    // registers
    logic [SDRAM_COL_WIDTH+SDRAM_ROW_WIDTH+SDRAM_BANK_WIDTH-1:0] addr_reg;
    logic [DATA_WIDTH-1:0] data_reg;
    logic we_reg;
    logic [DATA_WIDTH-1:0] q_reg;

    // aliases to decode the address register
    wire [SDRAM_COL_WIDTH-1:0]  col  = addr_reg[SDRAM_COL_WIDTH-1:0];
    wire [SDRAM_ROW_WIDTH-1:0]  row  = addr_reg[SDRAM_COL_WIDTH+SDRAM_ROW_WIDTH-1:SDRAM_COL_WIDTH];
    wire [SDRAM_BANK_WIDTH-1:0] bank = addr_reg[SDRAM_COL_WIDTH+SDRAM_ROW_WIDTH+SDRAM_BANK_WIDTH-1:SDRAM_COL_WIDTH+SDRAM_ROW_WIDTH];

    // SDRAM data output driver
    logic [SDRAM_DATA_WIDTH-1:0] sdram_dq_out;
    logic sdram_dq_oe;

    assign sdram_dq = sdram_dq_oe ? sdram_dq_out : {SDRAM_DATA_WIDTH{1'bZ}};

    // state machine
    always_comb begin
        next_state = state;

        // default to a NOP command
        next_cmd = CMD_NOP;

        case (state)
            // execute the initialisation sequence
            INIT: begin
                if (wait_counter == 0) begin
                    next_cmd = CMD_DESELECT;
                end else if (wait_counter == INIT_WAIT - 1) begin
                    next_cmd = CMD_PRECHARGE;
                end else if (wait_counter == INIT_WAIT + PRECHARGE_WAIT - 1) begin
                    next_cmd = CMD_AUTO_REFRESH;
                end else if (wait_counter == INIT_WAIT + PRECHARGE_WAIT + REFRESH_WAIT - 1) begin
                    next_cmd = CMD_AUTO_REFRESH;
                end else if (wait_counter == INIT_WAIT + PRECHARGE_WAIT + REFRESH_WAIT + REFRESH_WAIT - 1) begin
                    next_state = MODE;
                    next_cmd   = CMD_LOAD_MODE;
                end
            end

            // load the mode register
            MODE: begin
                if (load_mode_done) begin
                    next_state = IDLE;
                end
            end

            // wait for a read/write request
            IDLE: begin
                if (should_refresh) begin
                    next_state = REFRESH;
                    next_cmd   = CMD_AUTO_REFRESH;
                end else if (req) begin
                    next_state = ACTIVE;
                    next_cmd   = CMD_ACTIVE;
                end
            end

            // activate the row
            ACTIVE: begin
                if (active_done) begin
                    if (we_reg) begin
                        next_state = WRITE;
                        next_cmd   = CMD_WRITE;
                    end else begin
                        next_state = READ;
                        next_cmd   = CMD_READ;
                    end
                end
            end

            // execute a read command
            READ: begin
                if (read_done) begin
                    if (should_refresh) begin
                        next_state = REFRESH;
                        next_cmd   = CMD_AUTO_REFRESH;
                    end else if (req) begin
                        next_state = ACTIVE;
                        next_cmd   = CMD_ACTIVE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            // execute a write command
            WRITE: begin
                if (write_done) begin
                    if (should_refresh) begin
                        next_state = REFRESH;
                        next_cmd   = CMD_AUTO_REFRESH;
                    end else if (req) begin
                        next_state = ACTIVE;
                        next_cmd   = CMD_ACTIVE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            // execute an auto refresh
            REFRESH: begin
                if (refresh_done) begin
                    if (req) begin
                        next_state = ACTIVE;
                        next_cmd   = CMD_ACTIVE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end

            default: begin
                next_state = INIT;
            end
        endcase
    end

    // latch the next state
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= INIT;
            cmd   <= CMD_NOP;
        end else begin
            state <= next_state;
            cmd   <= next_cmd;
        end
    end

    // the wait counter is used to hold the current state for a number of clock
    // cycles
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            wait_counter <= '0;
        end else begin
            if (state != next_state) begin // state changing
                wait_counter <= '0;
            end else begin
                wait_counter <= wait_counter + 1'b1;
            end
        end
    end

    // the refresh counter is used to periodically trigger a refresh operation
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            refresh_counter <= '0;
        end else begin
            if (state == REFRESH && wait_counter == 0) begin
                refresh_counter <= '0;
            end else begin
                refresh_counter <= refresh_counter + 1'b1;
            end
        end
    end

    // latch the request
    always_ff @(posedge clk) begin
        if (start) begin
            // we need to multiply the address by two, because we are converting
            // from a 32-bit controller address to a 16-bit SDRAM address
            addr_reg <= (SDRAM_COL_WIDTH+SDRAM_ROW_WIDTH+SDRAM_BANK_WIDTH)'(addr) << 1;
            data_reg <= data;
            we_reg   <= we;
        end
    end

    // latch the output data as it's bursted from the SDRAM
    always_ff @(posedge clk) begin
        valid <= 1'b0;

        if (state == READ) begin
            if (first_word) begin
                q_reg[31:16] <= sdram_dq;
            end else if (read_done) begin
                q_reg[15:0] <= sdram_dq;
                valid <= 1'b1;
            end
        end
    end

    // set wait signals
    assign load_mode_done = (wait_counter == LOAD_MODE_WAIT - 1);
    assign active_done    = (wait_counter == ACTIVE_WAIT - 1);
    assign refresh_done   = (wait_counter == REFRESH_WAIT - 1);
    assign first_word     = (wait_counter == CAS_LATENCY);
    assign read_done      = (wait_counter == READ_WAIT - 1);
    assign write_done     = (wait_counter == WRITE_WAIT - 1);

    // the SDRAM should be refreshed when the refresh interval has elapsed
    assign should_refresh = (refresh_counter >= REFRESH_INTERVAL - 1);

    // a new request is only allowed at the end of the IDLE, READ, WRITE, and
    // REFRESH states
    assign start = (state == IDLE) ||
                   (state == READ && read_done) ||
                   (state == WRITE && write_done) ||
                   (state == REFRESH && refresh_done);

    // assert the acknowledge signal at the beginning of the ACTIVE state
    assign ack = (state == ACTIVE && wait_counter == 0);

    // set output data
    assign q = q_reg;

    // deassert the clock enable at the beginning of the INIT state
    assign sdram_cke = ~(state == INIT && wait_counter == 0);

    // set SDRAM control signals
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = cmd;

    // set SDRAM bank
    always_comb begin
        case (state)
            ACTIVE:  sdram_ba = bank;
            READ:    sdram_ba = bank;
            WRITE:   sdram_ba = bank;
            default: sdram_ba = '0;
        endcase
    end

    // set SDRAM address
    always_comb begin
        case (state)
            INIT:    sdram_a = 13'b0010000000000;
            MODE:    sdram_a = MODE_REG;
            ACTIVE:  sdram_a = row;
            READ:    sdram_a = {4'b0010, col};  // auto precharge
            WRITE:   sdram_a = {4'b0010, col};  // auto precharge
            default: sdram_a = '0;
        endcase
    end

    // decode the next 16-bit word from the write buffer
    always_comb begin
        sdram_dq_oe  = (state == WRITE);
        sdram_dq_out = data_reg[(BURST_LENGTH - wait_counter) * SDRAM_DATA_WIDTH - 1 -: SDRAM_DATA_WIDTH];
    end

    // set SDRAM data mask
    assign sdram_dqmh = 1'b0;
    assign sdram_dqml = 1'b0;

endmodule
