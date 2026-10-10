// stream_source.sv  -- OWNER: Person D
//
// Reads a pixel image from a hex file ($readmemh, one 2-digit hex byte
// per line, raster order) and drives it into the accelerator's input
// stream, honoring s_ready. Can optionally insert random valid-gaps to
// test that the accelerator doesn't lose/duplicate/reorder pixels when
// the source isn't always ready to send.
//
// Runtime config via plusargs (set by the invoking simulation command):
//   +INPUT=<path to hex file>      (required)
//   +GAPS=1                        (optional: insert random valid-low gaps)
//   +SEED=<int>                    (optional: gap RNG seed, default 1)

module stream_source #(
    parameter int WIDTH   = 8,
    parameter int HEIGHT  = 8,
    parameter int PIXEL_W = 8
) (
    input  logic clk,
    input  logic rst,
    output logic s_valid,
    input  logic s_ready,
    output logic [PIXEL_W-1:0] s_pixel,
    output logic s_sof,
    output logic s_eol,
    output logic s_eof,
    output logic done          // pulses 1 for one cycle after the last pixel is accepted
);

    logic [PIXEL_W-1:0] image [0:WIDTH*HEIGHT-1];
    string input_file;
    int    gaps_enable;
    int    seed;
    int    idx;         // 0 .. WIDTH*HEIGHT-1
    logic  gap_hold;     // when 1, force s_valid=0 this cycle (random gap)

    initial begin
        if (!$value$plusargs("INPUT=%s", input_file)) begin
            $display("ERROR: stream_source requires +INPUT=<hex file>");
            $finish;
        end
        $readmemh(input_file, image);
        if (!$value$plusargs("GAPS=%d", gaps_enable)) gaps_enable = 0;
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        idx = 0;
    end

    // simple LFSR-ish gap generator (good enough for a hackathon stall test)
    logic [31:0] rnd;
    initial rnd = 32'hDEADBEEF ^ seed;
    always_ff @(posedge clk) begin
        if (rst) rnd <= 32'hDEADBEEF ^ seed;
        else     rnd <= {rnd[30:0], rnd[31] ^ rnd[21] ^ rnd[1] ^ rnd[0]};
    end
    always_comb gap_hold = gaps_enable && (rnd[3:0] == 4'h0); // ~1/16 of cycles

    assign s_pixel = image[idx];
    assign s_sof   = (idx == 0);
    assign s_eol   = ((idx % WIDTH) == (WIDTH-1));
    assign s_eof   = (idx == WIDTH*HEIGHT-1);
    assign s_valid = (idx < WIDTH*HEIGHT) && !gap_hold;

    logic done_r;
    assign done = done_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            idx <= 0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (s_valid && s_ready) begin
                if (idx == WIDTH*HEIGHT-1) begin
                    done_r <= 1'b1;
                end
                idx <= idx + 1;
            end
        end
    end

endmodule
