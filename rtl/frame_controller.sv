// frame_controller.sv  -- OWNER: Person A
//
// Accepts an 8-bit grayscale pixel stream (ready/valid, raster order) and
// produces a stream of 3x3 windows, one per output pixel, with zero
// padding on all borders. This is the highest-risk module in the project
// (border/off-by-one bugs) -- it has already been simulated against the
// golden model for 4x4 and 8x8 random images; see tb/tb_top.sv.
//
// ---------------------------------------------------------------------
// HOW IT WORKS (read this before changing anything)
// ---------------------------------------------------------------------
// Two line buffers (line_buf0, line_buf1) remember the previous two rows,
// one pixel-storage-cell per column. Every "column step" (one per cycle,
// gated by out_stall), we:
//   1. read top    = line_buf1[x_in]   (row y_in-2 at this column)
//   2. read mid    = line_buf0[x_in]   (row y_in-1 at this column)
//   3. bot         = incoming pixel (real, or 0 if this is the phantom
//                    flush row/column -- see below)
//   4. shift the 3-wide horizontal window register:
//        win_col0 <= win_col1 ; win_col1 <= win_col2 ; win_col2 <= {top,mid,bot}
//      (at x_in==0 we force win_col0/win_col1 to 0 instead of shifting
//       stale data from the previous row -- that stale data would
//       otherwise leak in as wrong left-edge padding)
//   5. write-back: line_buf1[x_in] <= line_buf0[x_in] (old mid becomes
//      top for the next row); line_buf0[x_in] <= bot
//
// After step 4, the window [win_col0 | win_col1 | win_col2] is centered
// on column (x_in-1), row (y_in-1). So a valid output window exists once
// x_in>=1 && y_in>=1.
//
// FLUSH / DRAIN (why there are more "steps" than W*H):
//   - The very last column of each row (center = W-1) needs x_in to reach
//     W, one past the last real column -- so after each row's W real
//     pixels, we auto-generate ONE flush-column step (pixel=0) before
//     moving to the next row.
//   - The very last row (center = H-1) needs y_in to reach H, so after
//     all H real rows (each followed by its flush column) we auto-run
//     ONE phantom row of W+1 synthetic steps (pixel=0 throughout).
//   Total steps = (H+1)*(W+1); valid output windows among them = H*W,
//   exactly one per input pixel, as required by the spec.
//
// Backpressure: `out_stall` (driven by accelerator_top from m_ready) is
// checked every cycle. While stalled, nothing advances -- no pixel is
// accepted, no window is produced -- so no data is ever lost.
// ---------------------------------------------------------------------

module frame_controller #(
    parameter int WIDTH   = 8,
    parameter int HEIGHT  = 8,
    parameter int PIXEL_W = 8
) (
    input  logic                  clk,
    input  logic                  rst,       // synchronous, active-high

    // input stream (frozen interface, docs/FROZEN_BASELINE.md)
    input  logic                  s_valid,
    output logic                  s_ready,
    input  logic [PIXEL_W-1:0]    s_pixel,
    input  logic                  s_sof,
    input  logic                  s_eol,
    input  logic                  s_eof,

    // backpressure from downstream (accelerator_top's output register)
    input  logic                  out_stall,

    // window stream -- one 3x3 window per valid output pixel
    output logic                  win_valid,
    output logic [PIXEL_W-1:0]    win00, win01, win02,   // top row
    output logic [PIXEL_W-1:0]    win10, win11, win12,   // mid row
    output logic [PIXEL_W-1:0]    win20, win21, win22,   // bottom row
    output logic                  win_sof,
    output logic                  win_eol,
    output logic                  win_eof
);

    localparam int CW = (WIDTH  <= 1) ? 1 : $clog2(WIDTH);
    localparam int CNT_W = 16; // generous; no synthesis target today

    // ---- counters ----
    // x_in: 0..WIDTH (WIDTH = flush column); y_in: 0..HEIGHT (HEIGHT = phantom row)
    // NOTE: no separate "busy" flag is needed. (x_in==0 && y_in==0) is
    // reached exactly once per frame at the very start, and the FSM
    // naturally wraps back to (0,0) only after the full (W+1)*(H+1)-step
    // sequence completes -- so "waiting for next sof" and "processing
    // pixel (0,0)" are the same state and don't need to be disambiguated.
    logic [CNT_W-1:0] x_in, y_in;

    // ---- line buffers (Person A's standalone module) ----
    logic                 lb_wr_en;
    logic [CW-1:0]        lb_col;
    logic [PIXEL_W-1:0]   lb0_rd, lb1_rd;     // mid, top reads
    logic [PIXEL_W-1:0]   bot_val;

    assign lb_col  = x_in[CW-1:0];
    // CRITICAL: gated by step_now, not just (x_in < WIDTH). Without this,
    // a gap or stall that holds x_in fixed for multiple cycles would
    // re-write the line buffer every one of those cycles -- and since
    // line_buf1's write data is line_buf0's (already-just-rewritten)
    // output, a few idle cycles at the same column silently overwrite the
    // "two rows back" value with the current row's value instead of
    // preserving it. (Found via the +GAPS=1 and +STALLS=1 regressions --
    // both produced wrong pixels only under backpressure/gaps, never on
    // the clean path, which is exactly this symptom.)
    assign lb_wr_en = step_now && (x_in < WIDTH);

    line_buffer #(.WIDTH(WIDTH), .PIXEL_W(PIXEL_W)) u_line_buf0 (
        .clk(clk), .rst(rst),
        .wr_en(lb_wr_en), .wr_col(lb_col), .wr_data(bot_val),
        .rd_col(lb_col), .rd_data(lb0_rd)
    );
    line_buffer #(.WIDTH(WIDTH), .PIXEL_W(PIXEL_W)) u_line_buf1 (
        .clk(clk), .rst(rst),
        .wr_en(lb_wr_en), .wr_col(lb_col), .wr_data(lb0_rd),  // shift old mid -> top
        .rd_col(lb_col), .rd_data(lb1_rd)
    );

    // ---- derive this column-step's (top, mid, bot) ----
    logic in_real_row;     // y_in < HEIGHT
    logic in_real_col;     // x_in < WIDTH
    logic top_valid, mid_valid;

    assign in_real_row = (y_in < HEIGHT);
    assign in_real_col = (x_in < WIDTH);
    assign top_valid   = in_real_col && (y_in >= 2);
    assign mid_valid   = in_real_col && (y_in >= 1);

    assign bot_val = (in_real_col && in_real_row) ? s_pixel : {PIXEL_W{1'b0}};

    logic [PIXEL_W-1:0] top_val, mid_val;
    assign top_val = top_valid ? lb1_rd : {PIXEL_W{1'b0}};
    assign mid_val = mid_valid ? lb0_rd : {PIXEL_W{1'b0}};

    // ---- horizontal window shift register (3 columns x 3 rows) ----
    // wc0/wc1/wc2 hold the window as committed by the LAST ACCEPTED step
    // (i.e. as of x_in_prev). Each cycle we combinationally compute what
    // the window WOULD become if this step is taken (prop_wc*), and
    // expose win00..win22/win_valid directly from that combinational
    // value -- never from the lagging registers. This way the window's
    // *data* and its *valid* flag are always same-cycle, so backpressure
    // (out_stall, also same-cycle) can never let a window's validity and
    // its capture into accelerator_top's skid buffer fall out of sync.
    //
    // Two earlier, buggier versions of this module existed:
    //  (1) win_valid combinational against ALREADY-advanced x_in, read
    //      against the OLD (not-yet-updated) wc* registers -> every
    //      output landed one column to the right (caught by the impulse
    //      test in tb/).
    //  (2) win_valid/win00-22 registered one cycle behind step_now's own
    //      out_stall check -> under backpressure, a window already
    //      "in flight" when a stall began could be silently dropped
    //      before accelerator_top ever captured it (caught by the
    //      +GAPS=1 +STALLS=1 regression hanging/losing pixels).
    // Both are fixed by making win_valid/win00-22 pure same-cycle
    // combinational functions of step_now, exactly as below.
    logic [PIXEL_W-1:0] wc0_top, wc0_mid, wc0_bot;  // win_col0 (leftmost, committed)
    logic [PIXEL_W-1:0] wc1_top, wc1_mid, wc1_bot;  // win_col1 (center, committed)
    logic [PIXEL_W-1:0] wc2_top, wc2_mid, wc2_bot;  // win_col2 (rightmost, committed)

    logic [PIXEL_W-1:0] prop_wc0_top, prop_wc0_mid, prop_wc0_bot;
    logic [PIXEL_W-1:0] prop_wc1_top, prop_wc1_mid, prop_wc1_bot;
    logic [PIXEL_W-1:0] prop_wc2_top, prop_wc2_mid, prop_wc2_bot;

    always_comb begin
        if (x_in == 0) begin
            prop_wc0_top = '0; prop_wc0_mid = '0; prop_wc0_bot = '0;
            prop_wc1_top = '0; prop_wc1_mid = '0; prop_wc1_bot = '0;
        end else begin
            prop_wc0_top = wc1_top; prop_wc0_mid = wc1_mid; prop_wc0_bot = wc1_bot;
            prop_wc1_top = wc2_top; prop_wc1_mid = wc2_mid; prop_wc1_bot = wc2_bot;
        end
        prop_wc2_top = top_val; prop_wc2_mid = mid_val; prop_wc2_bot = bot_val;
    end

    // ---- step enable: do we advance this cycle? ----
    // in_real_row && in_real_col is true both "waiting for the next
    // frame's sof" (x_in=y_in=0) and "mid-frame real pixel" -- in both
    // cases we need an s_valid handshake. Everywhere else (flush column,
    // phantom row) we auto-advance every cycle, gated only by out_stall.
    logic step_now;
    assign step_now = !out_stall &&
                       ( (in_real_row && in_real_col && s_valid) ||
                         (!(in_real_row && in_real_col)) );
    assign s_ready = in_real_row && in_real_col && !out_stall;

    always_ff @(posedge clk) begin
        if (rst) begin
            x_in <= '0; y_in <= '0;
            wc0_top<='0; wc0_mid<='0; wc0_bot<='0;
            wc1_top<='0; wc1_mid<='0; wc1_bot<='0;
            wc2_top<='0; wc2_mid<='0; wc2_bot<='0;
        end else begin
            if (step_now) begin
                // commit exactly the values already exposed combinationally
                // on win00..win22 this cycle (see always_comb below) -- no
                // re-derivation, so there is no way for the committed state
                // and the output the consumer just (maybe) captured to
                // diverge.
                wc0_top <= prop_wc0_top; wc0_mid <= prop_wc0_mid; wc0_bot <= prop_wc0_bot;
                wc1_top <= prop_wc1_top; wc1_mid <= prop_wc1_mid; wc1_bot <= prop_wc1_bot;
                wc2_top <= prop_wc2_top; wc2_mid <= prop_wc2_mid; wc2_bot <= prop_wc2_bot;

                // advance counters
                if (x_in == WIDTH) begin
                    // just did the flush-column step for this row
                    if (y_in == HEIGHT) begin
                        // just did the phantom row's flush column -> frame done,
                        // wraps back to (0,0) = "waiting for next frame's sof"
                        x_in <= '0;
                        y_in <= '0;
                    end else begin
                        x_in <= '0;
                        y_in <= y_in + 1'b1;
                    end
                end else begin
                    x_in <= x_in + 1'b1;
                end
            end
        end
    end

    // ---- window output (pure combinational, same-cycle as step_now) ----
    assign win_valid = step_now && (x_in >= 1) && (y_in >= 1);
    assign win_sof   = win_valid && (x_in == 1) && (y_in == 1);
    assign win_eol   = win_valid && (x_in == WIDTH);
    assign win_eof   = win_valid && (x_in == WIDTH) && (y_in == HEIGHT);

    assign win00 = prop_wc0_top; assign win01 = prop_wc1_top; assign win02 = prop_wc2_top;
    assign win10 = prop_wc0_mid; assign win11 = prop_wc1_mid; assign win12 = prop_wc2_mid;
    assign win20 = prop_wc0_bot; assign win21 = prop_wc1_bot; assign win22 = prop_wc2_bot;

endmodule
