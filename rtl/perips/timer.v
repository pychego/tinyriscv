/*                                                                                                               
 */

`include "../core/defines.v"


// 32 bits count up timer module
module timer (

    input wire clk,
    input wire rst,

    input wire [31:0] data_i,
    input wire [31:0] addr_i,
    input wire        we_i,

    output reg  [31:0] data_o,
    output wire        int_sig_o  // 给出中断信号

);
/* timer产生的异步中断信号传递方向:
   timer -> tinyriscv(if_id) 打拍 -> clint(进入int_state == S_INT_ASYNC_ASSERT,)  要根据timer_int.c的仿真波形进行分析,超级复杂
   
*/

    localparam REG_CTRL = 4'h0;
    localparam REG_COUNT = 4'h4;
    localparam REG_VALUE = 4'h8;

    // [0]: timer enable
    // [1]: timer int enable
    // [2]: timer int pending, write 1 to clear it
    // timer_ctrl[2] <= (timer_ctrl[2] & (~data_i[2]))
    // pending, 等待状态: 中断处于有效状态,但是等待CPU响应该中断
    // addr offset: 0x00, 地址偏移是自定义的
    reg [31:0] timer_ctrl;

    // timer current count, read only
    // addr offset: 0x04
    reg [31:0] timer_count;

    // timer expired value 设定定时器中断发生的counter值
    // addr offset: 0x08
    reg [31:0] timer_value;


    assign int_sig_o = ((timer_ctrl[2] == 1'b1) && (timer_ctrl[1] == 1'b1))? `INT_ASSERT: `INT_DEASSERT;

    // counter
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            timer_count <= `ZeroWord;
        end else begin
            if (timer_ctrl[0] == 1'b1) begin
                timer_count <= timer_count + 1'b1;
                if (timer_count >= timer_value) begin
                    timer_count <= `ZeroWord;
                end
            end else begin
                timer_count <= `ZeroWord;
            end
        end
    end

    // write regs
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            timer_ctrl  <= `ZeroWord;
            timer_value <= `ZeroWord;
        end else begin
            if (we_i == `WriteEnable) begin
                case (addr_i[3:0])
                    REG_CTRL: begin
                        timer_ctrl <= {data_i[31:3], (timer_ctrl[2] & (~data_i[2])), data_i[1:0]};
                    end
                    REG_VALUE: begin
                        timer_value <= data_i;
                    end
                endcase
            end else begin  // 如果计时器中断到了，那么就设置中断标志,并暂停timer的enable
                if ((timer_ctrl[0] == 1'b1) && (timer_count >= timer_value)) begin
                    timer_ctrl[0] <= 1'b0;
                    timer_ctrl[2] <= 1'b1;
                end
            end
        end
    end

    // read regs
    always @(*) begin
        if (rst == `RstEnable) begin
            data_o = `ZeroWord;
        end else begin
            case (addr_i[3:0])
                REG_VALUE: begin
                    data_o = timer_value;
                end
                REG_CTRL: begin
                    data_o = timer_ctrl;
                end
                REG_COUNT: begin
                    data_o = timer_count;
                end
                default: begin
                    data_o = `ZeroWord;
                end
            endcase
        end
    end

endmodule
