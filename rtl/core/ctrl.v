/*
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
 Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */

`include "defines.v"

// 控制模块
// 发出跳转、暂停流水线信号
module ctrl (

    input wire rst,

    // from ex
    input wire                jump_flag_i,
    input wire [`InstAddrBus] jump_addr_i,
    input wire                hold_flag_ex_i,   // 除法运算暂停标志

    // from rib  总线发出的流水线暂停信号
    input wire hold_flag_rib_i,

    // from jtag
    input wire jtag_halt_flag_i,

    // from clint
    input wire hold_flag_clint_i,       // 中断暂停标志(async和sync)

    // to pc_reg, if_id, id_ex, clint, 实际上clint中的该信号没使用
    output reg [`Hold_Flag_Bus] hold_flag_o,

    // to pc_reg  直接将从ex接收的信号转发
    output reg                jump_flag_o,
    output reg [`InstAddrBus] jump_addr_o

);


    always @(*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        // 默认不暂停
        hold_flag_o = `Hold_None;
        // 按优先级处理不同模块的请求
        /* 对于跳转指令, div暂停, 同步中断这几个, ex执行发出跳转之后, 下一拍clk就直接pc跳转了
        */
        if (jump_flag_i == `JumpEnable || hold_flag_ex_i == `HoldEnable || hold_flag_clint_i == `HoldEnable) begin
            // 对于跳转(Jump Instruction)操作、来自ex阶段的暂停(div)、来自中断模块(同步中断ecall, ebreak, timer)的暂停则暂停整条流水线。
            hold_flag_o = `Hold_Id;
        end else if (hold_flag_rib_i == `HoldEnable) begin
            // 对于总线暂停，只需要暂停PC寄存器，让译码和执行阶段继续运行。
            hold_flag_o = `Hold_Pc;
        end else if (jtag_halt_flag_i == `HoldEnable) begin
            // 暂停整条流水线(清空if-id,id-ex流水线寄存器,pc根据逻辑修改)
            hold_flag_o = `Hold_Id;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule

/*
对于jump指令,在ex阶段当拍(id-ex打拍后)可以发出jump_addr和jump_flag, 然后本周期ctrl就会处理得到hold_flag_o(Hold_ID)
给各个流水线寄存器打拍的输入(if-id,id-ex),注意当前周期的pc不变,pc的改变受clk控制;
clk到来后,if-id,id-ex流水线寄存器都清空,pc变为jump_addr,
pc取值作为第一级,不需要流水线寄存器,只需要根据控制信号改变pc即可

对于div指令, 0x10为div指令的地址pc_o
    除法开始...
        clk0到来后, pc_o为0x10, 译码id为0x0C, ex执行0x08
        clk1到来后, pc_o为0x14, 译码id为0x10,译出div指令, ex执行0x0C
        clk2到来后, pc_o为0x18, 译码id为0x14, ex执行0x10,输出流水线暂停指令给ctrl, 并输出跳转使能和跳转地址
        ex当拍出jump_flag, jump_flag
        clk3的到来,pc_o根据跳转地址跳转到0x10 + 0x04 = 0x14, 译码停止, ex停止
     除法结束...
         clk0到来,除法结束,这个周期pc_o还是0x14,但是译码id空档,ex执行空档
         clk1到来,pc_o为0x18,译码id为0x14,ex执行空档!!!
         clk2到来, pc_o为0x1c, 译码id为0x18, ex执行0x14

对于timer定时器中断,
    timer直接发送int_flag, 经过if-id流水线寄存器打拍,送到clint中,

对三级流水线的理解: 从复位开始,复位之后撤销, pc=0,等clk上升沿,
复位撤销后到第一个clk到来, 为第一级流水线,
译码阶段到第二个clk到来,为第二极流水线,
执行阶段到第三个clk到来, 为第三极流水线,
即第一条指令在系统复位后的三拍出结果
*/
