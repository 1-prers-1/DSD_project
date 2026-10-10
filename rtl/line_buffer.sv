// line_buffer.sv  -- OWNER: Person A
//
// Remembers one full row of pixels (WIDTH entries) so that, combined with
// a second instance of this module, the window generator can see 3 rows
// at once (current incoming row + 2 remembered rows) while pixels only
// ever arrive one at a time, left to right, top to bottom.
//
// Usage: instantiate TWO of these in frame_controller.sv.
//   line_buf0 remembers row N-1 (the most recent completed row)
//   line_buf1 remembers row N-2 (the row before that)
// On each accepted pixel:
//   line_buf1[col] <= line_buf0[col]   (shift older row down)
//   line_buf0[col] <= new pixel         (store current row as it streams in)
//
// This module itself is just a single shift-register row store; the
// "two instances" wiring happens in frame_controller.sv.

module line_buffer #(
    parameter int WIDTH   = 8,
    parameter int PIXEL_W = 8
) (
    input  logic                  clk,
    input  logic                  rst,       // synchronous, active-high
    input  logic                  wr_en,     // pulse once per accepted pixel
    input  logic [$clog2(WIDTH)-1:0] wr_col, // which column is being written
    input  logic [PIXEL_W-1:0]    wr_data,
    input  logic [$clog2(WIDTH)-1:0] rd_col, // column to read back (combinational)
    output logic [PIXEL_W-1:0]    rd_data
);

    logic [PIXEL_W-1:0] mem [0:WIDTH-1];

    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < WIDTH; i = i + 1)
                mem[i] <= '0;
        end else if (wr_en) begin
            mem[wr_col] <= wr_data;
        end
    end

    assign rd_data = mem[rd_col];

endmodule
