module running_dft_pe #(
    parameter W                 = 22,
    parameter ITER              = 16,
    parameter N                 = 16,
    parameter ANG_W             = 24,
    parameter SINGLE_CYCLE_COMP = 0,
    parameter PAPER_TRUNC_SCALE = 0
)
(
    input                      clk,
    input                      rst_n,
    input                      clear,       
    input                      sample_en,
    input  signed [W-1:0]      ds_re,       
    input  signed [W-1:0]      ds_im,
    input  signed [W-1:0]      s_re,       
    input  signed [W-1:0]      s_im,
    input  signed [ANG_W-1:0]  theta,
    output reg signed [W-1:0]  f_re,       
    output reg signed [W-1:0]  f_im,        
    output reg                 done,        
    output                     valid        
);

    reg [7:0] warm_cnt;       
    reg busy;
    reg drop;                
    reg signed [W-1:0] in_reg_re, in_reg_im;

    wire warm = (warm_cnt < N);
    assign valid = !warm;


    wire signed [W-1:0] add_re = warm ? s_re : ds_re;
    wire signed [W-1:0] add_im = warm ? s_im : ds_im;

    wire signed [W-1:0] sum_re = f_re + add_re;
    wire signed [W-1:0] sum_im = f_im + add_im;

    wire start = sample_en && !busy && !clear;

    wire signed [W-1:0] rot_re, rot_im;
    wire rot_done;

    cordic_rotate #(
        .W(W),
        .ITER(ITER),
        .ANG_W(ANG_W),
        .SINGLE_CYCLE_COMP(SINGLE_CYCLE_COMP),
        .PAPER_TRUNC_SCALE(PAPER_TRUNC_SCALE)
    ) rot (
        .clk(clk), .rst_n(rst_n), .start(start),
        .x_in(sum_re), .y_in(sum_im), .theta(theta),
        .x_out(rot_re), .y_out(rot_im), .done(rot_done)
    );

    always @(posedge clk) begin
        done <= 1'b0;

        if (!rst_n) begin
            f_re      <= 0;
            f_im      <= 0;
            in_reg_re <= 0;
            in_reg_im <= 0;
            warm_cnt  <= 0;
            busy      <= 1'b0;
            drop      <= 1'b0;
        end
        else if (clear) begin
            f_re      <= 0;
            f_im      <= 0;
            in_reg_re <= 0;
            in_reg_im <= 0;
            warm_cnt  <= 0;
            if (rot_done) begin
                busy <= 1'b0;
                drop <= 1'b0;
            end
            else begin
                drop <= busy;
            end
        end
        else begin
            if (start) begin
                in_reg_re <= add_re;
                in_reg_im <= add_im;
                busy      <= 1'b1;
            end

            if (rot_done) begin
                busy <= 1'b0;
                drop <= 1'b0;
                if (!drop) begin
                    f_re <= rot_re;
                    f_im <= rot_im;
                    done <= 1'b1;
                    if (warm_cnt < N)
                        warm_cnt <= warm_cnt + 1;
                end
            end
        end
    end

endmodule
