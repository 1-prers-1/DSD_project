// tb_top.sv  -- OWNER: Person D
//
// Top-level testbench: clock/reset generation, instantiates the DUT
// (accelerator_top) plus stream_source and stream_sink, runs until the
// sink has collected a full frame (or a timeout fires), writes the
// output hex file, then finishes.
//
// Run with (see scripts/run_sim.sh for the full set of regression runs):
//   vvp sim.out +INPUT=golden_model/vectors/t0_input.hex \
//               +OUTPUT=sim_out/t0_rtl_output.hex +SIZE=8 +GAPS=1 +STALLS=1

module tb_top;

    localparam int PIXEL_W = 8;
    localparam int COEFF_W = 10;
    localparam int ACC_W   = 24;

    int size;
    initial if (!$value$plusargs("SIZE=%d", size)) size = 8;

    // WIDTH/HEIGHT are `parameter` (not `localparam`) so they can be
    // overridden at compile time with `iverilog -Ptb_top.WIDTH=4
    // -Ptb_top.HEIGHT=4 ...` -- e.g. to run the 4x4 fallback size from
    // docs/FROZEN_BASELINE.md without editing this file. The corresponding
    // hex vectors and +SIZE plusarg (used only for display/sanity, not
    // array sizing) must be generated at the matching size.
    parameter int WIDTH  = 8;
    parameter int HEIGHT = 8;

    logic clk = 0;
    logic rst;

    always #5 clk = ~clk;  // 100MHz-equivalent, period=10 (units irrelevant for functional sim)

    logic s_valid, s_ready, s_sof, s_eol, s_eof;
    logic [PIXEL_W-1:0] s_pixel;
    logic m_valid, m_ready, m_sof, m_eol, m_eof;
    logic [PIXEL_W-1:0] m_pixel;
    logic src_done, sink_done;

    accelerator_top #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .PIXEL_W(PIXEL_W),
        .COEFF_W(COEFF_W), .ACC_W(ACC_W)
    ) dut (
        .clk(clk), .rst(rst),
        .s_valid(s_valid), .s_ready(s_ready), .s_pixel(s_pixel),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    stream_source #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .PIXEL_W(PIXEL_W)) src (
        .clk(clk), .rst(rst),
        .s_valid(s_valid), .s_ready(s_ready), .s_pixel(s_pixel),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .done(src_done)
    );

    stream_sink #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .PIXEL_W(PIXEL_W)) snk (
        .clk(clk), .rst(rst),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .done(sink_done)
    );

    // ---- reset ----
    initial begin
        rst = 1;
        repeat (4) @(posedge clk);
        rst = 0;
    end

    // ---- waveform dump (for the demo) ----
    initial begin
        $dumpfile("sim_out/wave.vcd");
        $dumpvars(0, tb_top);
    end

    // ---- completion / timeout ----
    initial begin
        int timeout_cycles;
        timeout_cycles = (WIDTH+1)*(HEIGHT+1)*20 + 1000; // generous margin for stalls/gaps
        fork
            begin
                @(posedge sink_done);
            end
            begin
                repeat (timeout_cycles) @(posedge clk);
                $display("TIMEOUT: sink never collected a full frame (idx stuck?)");
                $display("  DIAG: dut.u_frame_controller.x_in=%0d y_in=%0d",
                          dut.u_frame_controller.x_in, dut.u_frame_controller.y_in);
                $display("  DIAG: s_valid=%b s_ready=%b m_valid=%b m_ready=%b out_stall=%b",
                          s_valid, s_ready, m_valid, m_ready, dut.out_stall);
                $display("  DIAG: src idx=%0d done=%b  sink idx=%0d done=%b",
                          src.idx, src_done, snk.idx, sink_done);
                $fatal(1);
            end
        join_any
        disable fork;

        @(posedge clk); // let last writes settle
        snk.write_output();
        $display("SIMULATION DONE at time %0t", $time);
        $finish;
    end

endmodule
