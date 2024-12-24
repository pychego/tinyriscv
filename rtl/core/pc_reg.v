`include "defines.v"

//  PC寄存器模块, PC寄存器是一个独立的寄存器, 不占用32个通用寄存器位置
/*  作为Master1从AHB总线上取指
*/
module pc_reg (

    input wire clk,
    input wire rst,

    // 下面三个输入来自ctrl模块
    /* 优先级: jump > hold_flag > pc_o + 4
    */
    input wire                  jump_flag_i,       // 跳转标志
    input wire [  `InstAddrBus] jump_addr_i,       // 跳转地址
    input wire [`Hold_Flag_Bus] hold_flag_i,       // 流水线暂停标志, 来源于rib模块
    // 来自jtag模块
    input wire                  jtag_reset_flag_i, // 复位标志

    // pc_o 输出到if_id模块,同时作为tinyriscv的接口输出到总线
    output reg [`InstAddrBus] pc_o  // PC指针,32bit寄存器足够存放指令地址了
    

);


    always @(posedge clk) begin
        // 复位
        if (rst == `RstEnable || jtag_reset_flag_i == 1'b1) begin
            pc_o <= `CpuResetAddr;
            // 跳转
        end else if (jump_flag_i == `JumpEnable) begin
            pc_o <= jump_addr_i;
            // 暂停
        end else if (hold_flag_i >= `Hold_Pc) begin
            pc_o <= pc_o;
            // 地址加4
        end else begin
            pc_o <= pc_o + 4'h4;
        end
    end

endmodule
