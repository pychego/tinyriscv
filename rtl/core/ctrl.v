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
            // 对于跳转操作、来自ex阶段的暂停(div)、来自中断模块(同步中断ecall, ebreak, timer)的暂停则暂停整条流水线。
            hold_flag_o = `Hold_Id;
        end else if (hold_flag_rib_i == `HoldEnable) begin
            // 对于总线暂停，只需要暂停PC寄存器，让译码和执行阶段继续运行。
            hold_flag_o = `Hold_Pc;
        end else if (jtag_halt_flag_i == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule
