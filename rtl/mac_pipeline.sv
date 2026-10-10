// mac_pipeline.sv  -- OWNER: Person B
//
// Takes a 3x3 window of pixels and computes the fixed sharpen kernel's
// signed multiply-accumulate, then saturates to [0,255].
//
// Kernel (frozen, see docs/FROZEN_BASELINE.md):
//    0  -1   0
//   -1   5  -1
//    0  -1   0
// bias = 0, shift = 0
//
// Hand check (also in golden_model/golden_sharpen.py self_check()):
//   window = [10 20 30 / 40 50 60 / 70 80 90]
//   sum = 0*10 -1*20 +0*30 -1*40 +5*50 -1*60 +0*70 -1*80 +0*90
//       = -20-40+250-60-80 = 50  -> clamp(50,0,255) = 50
//
// Combinational for today's scope (no pipeline registers) -- fine, since
// we're not targeting a clock-frequency number, just correctness. Adding
// registers later (one stage per named step: partial products, adder
// tree, saturate) is a safe follow-up once this is proven correct.

module mac_pipeline #(
    parameter int PIXEL_W = 8,
    parameter int COEFF_W = 10,
    parameter int ACC_W   = 24
) (
    input  logic [PIXEL_W-1:0] win00, win01, win02,
    input  logic [PIXEL_W-1:0] win10, win11, win12,
    input  logic [PIXEL_W-1:0] win20, win21, win22,
    output logic [PIXEL_W-1:0] result
);

    // frozen sharpen kernel, signed
    localparam signed [COEFF_W-1:0] C00 =  0, C01 = -1, C02 =  0;
    localparam signed [COEFF_W-1:0] C10 = -1, C11 =  5, C12 = -1;
    localparam signed [COEFF_W-1:0] C20 =  0, C21 = -1, C22 =  0;
    localparam signed [ACC_W-1:0]   BIAS = 0;

    // sign-extend each unsigned pixel into a signed value one bit wider
    // than PIXEL_W (pixels are always >=0, so this is purely a safety
    // margin for the signed multiply, not a real sign bit).
    function automatic logic signed [PIXEL_W:0] sx(input logic [PIXEL_W-1:0] p);
        return $signed({1'b0, p});
    endfunction

    logic signed [ACC_W-1:0] sum;
    always_comb begin
        sum = BIAS
            + (sx(win00) * C00) + (sx(win01) * C01) + (sx(win02) * C02)
            + (sx(win10) * C10) + (sx(win11) * C11) + (sx(win12) * C12)
            + (sx(win20) * C20) + (sx(win21) * C21) + (sx(win22) * C22);
    end

    // saturate to [0,255] (shift=0 for the frozen baseline, so no shift here)
    always_comb begin
        if (sum < 0)
            result = 8'd0;
        else if (sum > 255)
            result = 8'd255;
        else
            result = sum[PIXEL_W-1:0];
    end

endmodule
