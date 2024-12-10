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

// PC寄存器模块, PC寄存器是一个独立的寄存器, 不占用32个通用寄存器位置
/*  作为Master1从AHB总线上取指
*/
module pc_reg (

    input wire clk,
    input wire rst,

    // 下面三个输入来自ctrl模块
    input wire                  jump_flag_i,       // 跳转标志
    input wire [  `InstAddrBus] jump_addr_i,       // 跳转地址
    input wire [`Hold_Flag_Bus] hold_flag_i,       // 流水线暂停标志
    // 来自jtag模块
    input wire                  jtag_reset_flag_i, // 复位标志

    // pc_o 输出到if_id模块,同时作为tinyriscv的接口输出到AHB总线
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
