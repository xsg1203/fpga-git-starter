//==========================================================================
// ov5640_capture.v  —  DVP 8bit -> RGB565 像素流
// OV5640 在 RGB565 模式下每像素两字节：
//   字节1 = {R[4:0], G[5:3]}   字节2 = {G[2:0], B[4:0]}
// 拼接后 pix = {R[4:0],G[5:3],G[2:0],B[4:0]}，与 VGA 输出位序一致
//==========================================================================
`timescale 1ns / 1ps

module ov5640_capture (
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        vsync,       // 高有效，帧起始
    input  wire        href,        // 高有效，行有效
    input  wire [7:0]  data,
    output reg  [15:0] pix,
    output reg         pix_vld,     // 单拍，pix / cx / cy 同时有效
    output reg  [9:0]  cx,
    output reg  [9:0]  cy,
    output reg         frame_start  // VSYNC 上升沿单拍
);

    reg        vsync_d, href_d;
    reg        byte_sel;
    reg [7:0]  b1;
    reg [9:0]  xcnt, ycnt;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d     <= 1'b0;
            href_d      <= 1'b0;
            byte_sel    <= 1'b0;
            b1          <= 8'd0;
            pix         <= 16'd0;
            pix_vld     <= 1'b0;
            cx          <= 10'd0;
            cy          <= 10'd0;
            xcnt        <= 10'd0;
            ycnt        <= 10'd0;
            frame_start <= 1'b0;
        end else begin
            vsync_d     <= vsync;
            href_d      <= href;
            pix_vld     <= 1'b0;
            frame_start <= vsync & ~vsync_d;

            if (vsync) begin
                xcnt     <= 10'd0;
                ycnt     <= 10'd0;
                byte_sel <= 1'b0;
            end else if (href) begin
                if (!byte_sel) begin
                    b1       <= data;
                    byte_sel <= 1'b1;
                end else begin
                    pix      <= {b1, data};
                    pix_vld  <= 1'b1;
                    cx       <= xcnt;
                    cy       <= ycnt;
                    xcnt     <= xcnt + 10'd1;
                    byte_sel <= 1'b0;
                end
            end else begin
                byte_sel <= 1'b0;
                if (href_d) ycnt <= ycnt + 10'd1;
            end
        end
    end

endmodule
