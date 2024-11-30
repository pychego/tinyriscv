`timescale 1ns / 1ps

`include "defines.v"
module div_tb ();

    reg                clk;
    reg                rst;

    reg [    `RegBus]  dividend_i;  // 被除数
    reg [    `RegBus]  divisor_i;  // 除数
    reg                start_i;  // 开始信号，运算期间这个信号需要一直保持有效
    reg [        2:0 ] op_i;  // 具体是哪一条指令
    reg [`RegAddrBus]  reg_waddr_i;  // 运算结束后需要写的寄存器


    wire [    `RegBus]  result_o;  // 除法结果，高32位是余数，低32位是商
    wire                ready_o;  // 运算结束信号
    wire                busy_o;  // 正在运算信号
    wire [`RegAddrBus]  reg_waddr_o;  // 运算结束后需要写的寄存器

    initial begin
        dividend_i = 15;
        divisor_i = 3;
        start_i = 0;
        op_i = `INST_DIVU;
        reg_waddr_i = 12;
        clk = 0;
        rst = 0;
        #104 rst = 1;
        #104 start_i = 1;
    end

    always #10 clk = ~clk;

        div u_div (
        .clk        (clk),
        .rst        (rst),
        .dividend_i (dividend_i),
        .divisor_i  (divisor_i),
        .start_i    (start_i),
        .op_i       (op_i),
        .reg_waddr_i(reg_waddr_i),
        .result_o   (result_o),
        .ready_o    (ready_o),
        .busy_o     (busy_o),
        .reg_waddr_o(reg_waddr_o)
    );




endmodule
