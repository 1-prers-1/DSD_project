// accelerator_top.sv  -- integration (owned jointly, mainly Person A)
//
// Wires: frame_controller (Person A) --window--> mac_pipeline (Person B)
//        --> 1-entry output skid register --> external m_* stream
//
// The skid register is what makes `m_valid` hold steady and `m_pixel`
// stable while the sink stalls (m_ready=0), satisfying the "no loss,
// no corruption under backpressure" requirement. frame_controller is
// told to stall (out_stall) whenever this register is full and not
// being drained this cycle, so a new window is never produced while
// the previous one is still waiting to be consumed.

module accelerator_top #(
    parameter int WIDTH   = 8,
    parameter int HEIGHT  = 8,
    parameter int PIXEL_W = 8,
    parameter int COEFF_W = 10,
    parameter int ACC_W   = 24
) (
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  s_valid,
    output logic                  s_ready,
    input  logic [PIXEL_W-1:0]    s_pixel,
    input  logic                  s_sof,
    input  logic                  s_eol,
    input  logic                  s_eof,

    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [PIXEL_W-1:0]    m_pixel,
    output logic                  m_sof,
    output logic                  m_eol,
    output logic                  m_eof
);

    logic win_valid, win_sof, win_eol, win_eof;
    logic [PIXEL_W-1:0] win00,win01,win02,win10,win11,win12,win20,win21,win22;
    logic out_stall;
    logic [PIXEL_W-1:0] mac_result;

    frame_controller #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .PIXEL_W(PIXEL_W)
    ) u_frame_controller (
        .clk(clk), .rst(rst),
        .s_valid(s_valid), .s_ready(s_ready), .s_pixel(s_pixel),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .out_stall(out_stall),
        .win_valid(win_valid),
        .win00(win00), .win01(win01), .win02(win02),
        .win10(win10), .win11(win11), .win12(win12),
        .win20(win20), .win21(win21), .win22(win22),
        .win_sof(win_sof), .win_eol(win_eol), .win_eof(win_eof)
    );

    mac_pipeline #(
        .PIXEL_W(PIXEL_W), .COEFF_W(COEFF_W), .ACC_W(ACC_W)
    ) u_mac_pipeline (
        .win00(win00), .win01(win01), .win02(win02),
        .win10(win10), .win11(win11), .win12(win12),
        .win20(win20), .win21(win21), .win22(win22),
        .result(mac_result)
    );

    // ---- 1-entry output skid register ----
    logic                 m_valid_r;
    logic [PIXEL_W-1:0]   m_pixel_r;
    logic                 m_sof_r, m_eol_r, m_eof_r;

    assign out_stall = m_valid_r && !m_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            m_valid_r <= 1'b0;
            m_sof_r <= 1'b0; m_eol_r <= 1'b0; m_eof_r <= 1'b0;
            m_pixel_r <= '0;
        end else begin
            if (m_valid_r && m_ready) begin
                m_valid_r <= 1'b0; // consumed this cycle
            end
            if (win_valid && !out_stall) begin
                m_pixel_r <= mac_result;
                m_sof_r   <= win_sof;
                m_eol_r   <= win_eol;
                m_eof_r   <= win_eof;
                m_valid_r <= 1'b1;
            end
        end
    end

    assign m_valid = m_valid_r;
    assign m_pixel = m_pixel_r;
    assign m_sof   = m_sof_r;
    assign m_eol   = m_eol_r;
    assign m_eof   = m_eof_r;

endmodule
