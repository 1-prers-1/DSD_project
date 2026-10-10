// stream_sink.sv  -- OWNER: Person D
//
// Collects the accelerator's output stream into memory and writes it to
// a hex file for golden_model/compare.py to check. Can optionally stall
// m_ready to test that the accelerator correctly HOLDS its output (no
// corruption, no loss) while the sink isn't ready.
//
// Runtime config via plusargs:
//   +OUTPUT=<path to write output hex file>   (required)
//   +STALLS=1                                  (optional: random m_ready-low stalls)
//   +SEED=<int>                                (optional: stall RNG seed, default 2)

module stream_sink #(
    parameter int WIDTH   = 8,
    parameter int HEIGHT  = 8,
    parameter int PIXEL_W = 8
) (
    input  logic clk,
    input  logic rst,
    input  logic m_valid,
    output logic m_ready,
    input  logic [PIXEL_W-1:0] m_pixel,
    input  logic m_sof,
    input  logic m_eol,
    input  logic m_eof,
    output logic done          // pulses 1 for one cycle after the last pixel is collected
);

    logic [PIXEL_W-1:0] result [0:WIDTH*HEIGHT-1];
    string output_file;
    int    stalls_enable;
    int    seed;
    int    idx;
    logic  stall_hold;

    // sanity counters -- checked by tb_top at the end of the run
    int unsigned sof_count, eol_count, eof_count;

    initial begin
        if (!$value$plusargs("OUTPUT=%s", output_file)) begin
            $display("ERROR: stream_sink requires +OUTPUT=<hex file path>");
            $finish;
        end
        if (!$value$plusargs("STALLS=%d", stalls_enable)) stalls_enable = 0;
        if (!$value$plusargs("SEED=%d", seed)) seed = 2;
        idx = 0;
        sof_count = 0; eol_count = 0; eof_count = 0;
    end

    logic [31:0] rnd;
    initial rnd = 32'hC0FFEE00 ^ seed;
    always_ff @(posedge clk) begin
        if (rst) rnd <= 32'hC0FFEE00 ^ seed;
        else     rnd <= {rnd[30:0], rnd[31] ^ rnd[21] ^ rnd[1] ^ rnd[0]};
    end
    always_comb stall_hold = stalls_enable && (rnd[3:0] < 4'h3); // ~3/16 of cycles stalled

    assign m_ready = !stall_hold;

    logic done_r;
    assign done = done_r;

    // held-beat stability check: while m_valid && !m_ready, m_pixel/sof/eol/eof
    // must not change. Flag a violation loudly if it ever does.
    logic                have_prev;
    logic [PIXEL_W-1:0]  prev_pixel;
    logic                prev_sof, prev_eol, prev_eof;

    always_ff @(posedge clk) begin
        if (rst) begin
            idx <= 0;
            done_r <= 1'b0;
            sof_count <= 0; eol_count <= 0; eof_count <= 0;
            have_prev <= 1'b0;
        end else begin
            done_r <= 1'b0;

            // stability check against the previous cycle's held beat
            if (have_prev) begin
                if (m_pixel !== prev_pixel || m_sof !== prev_sof ||
                    m_eol !== prev_eol || m_eof !== prev_eof) begin
                    $display("ASSERTION FAILURE @%0t: held output beat changed while stalled! prev_pixel=%0d new_pixel=%0d",
                              $time, prev_pixel, m_pixel);
                    $fatal(1);
                end
            end
            have_prev <= m_valid && !m_ready;
            prev_pixel <= m_pixel; prev_sof <= m_sof; prev_eol <= m_eol; prev_eof <= m_eof;

            if (m_valid && m_ready) begin
                result[idx] <= m_pixel;
                if (m_sof) sof_count <= sof_count + 1;
                if (m_eol) eol_count <= eol_count + 1;
                if (m_eof) eof_count <= eof_count + 1;
                if (idx == WIDTH*HEIGHT-1) begin
                    done_r <= 1'b1;
                end
                idx <= idx + 1;
            end
        end
    end

    task automatic write_output();
        int fh;
        fh = $fopen(output_file, "w");
        if (fh == 0) begin
            $display("ERROR: could not open %s for writing", output_file);
            $finish;
        end
        for (int i = 0; i < WIDTH*HEIGHT; i++) begin
            $fwrite(fh, "%02x\n", result[i]);
        end
        $fclose(fh);
        $display("stream_sink: wrote %0d pixels to %s", WIDTH*HEIGHT, output_file);
        $display("stream_sink: sof_count=%0d (expect 1) eol_count=%0d (expect %0d) eof_count=%0d (expect 1)",
                  sof_count, eol_count, HEIGHT, eof_count);
        if (sof_count != 1 || eol_count != HEIGHT || eof_count != 1) begin
            $display("MARKER CHECK: FAIL");
        end else begin
            $display("MARKER CHECK: PASS");
        end
    endtask

endmodule
