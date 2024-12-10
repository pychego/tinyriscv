/*                                                                      
PC寄存器模块的输出pc_o会连接到外设rom模块的地址输入，
又由于rom的读取是组合逻辑，因此每一个时钟上升沿到来之前(时序是满足要求的)，从rom输出的指令
已经稳定在if_id模块的输入，当时钟上升沿到来时指令就会输出到id模块。

取到的指令和指令地址会输入到if_id模块(if_id.v)，if_id模块是一个时序电路，作用是将输入的信号打一
拍后再输出到译码(id.v)模块
 */

`include "defines.v"

// if_id模块: 将inst指令向译码模块id传递
module if_id (

    input wire clk,
    input wire rst,

    input wire [    `InstBus] inst_i,      // 指令内容, 来自rom模块
    input wire [`InstAddrBus] inst_addr_i, // 指令地址, 来自pc_reg模块

    input wire [`Hold_Flag_Bus] hold_flag_i,  // 流水线暂停标志, 来自ctrl模块

    input  wire [`INT_BUS] int_flag_i,  // 外设中断输入信号, 来自timer模块
    output wire [`INT_BUS] int_flag_o,  // 外设中断输出信号, 传递给clint模块

    output wire [    `InstBus] inst_o,      // 指令内容, 传递给译码模块id
    output wire [`InstAddrBus] inst_addr_o  // 指令地址

);

    /* 不太明白这时候的状态
    好像是后面两级流水线都暂停了? 然后inst_o,inst_addr_o都变为默认值,int_flag_o为0
    */
    wire hold_en = (hold_flag_i >= `Hold_If);

    wire                                      [`InstBus] inst;
    /* 这里体现出三级流水线的第一级, 第一个clk上升沿到来后pc_o+4, 然后在第二个clk上升沿到来之前
    从rom中取到的inst就稳定在if_id模块的输入, 当第二个clk上升沿到来时inst就会输出到id模块
    */
    gen_pipe_dff #(32) inst_ff (
        clk,
        rst,
        hold_en,
        `INST_NOP,
        inst_i,
        inst
    );
    assign inst_o = inst;

    wire [`InstAddrBus] inst_addr;
    gen_pipe_dff #(32) inst_addr_ff (
        clk,
        rst,
        hold_en,
        `ZeroWord,
        inst_addr_i,
        inst_addr
    );
    assign inst_addr_o = inst_addr;

    wire [`INT_BUS] int_flag;
    gen_pipe_dff #(8) int_ff (
        clk,
        rst,
        hold_en,
        `INT_NONE,
        int_flag_i,
        int_flag
    );
    assign int_flag_o = int_flag;

endmodule
