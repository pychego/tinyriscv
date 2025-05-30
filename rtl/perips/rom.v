/*                                                                      
 Copyright 2020 Blue Liang, liangkangnan@163.com
                                                                         
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

`include "../core/defines.v"


module rom (

    input wire clk,
    input wire rst,

    input wire               we_i,    // write enable
    input wire [`MemAddrBus] addr_i,  // addr
    input wire [    `MemBus] data_i,

    output reg [`MemBus] data_o  // read data conbinational output

);
    // 生成包含RomNum个MemBus位的寄存器数组
    reg [`MemBus] _rom[0:`RomNum - 1];


    always @(posedge clk) begin
        if (we_i == `WriteEnable) begin
            _rom[addr_i[31:2]] <= data_i;
        end
    end

    /* 为什么取地址的指令要取31:2位，而不是31:0位？
       因为pc_o即addr_i每次加4，所以addr_i[1:0]是00，addr_i[31:2]指示pc_o自加了几次
    */
    always @(*) begin
        if (rst == `RstEnable) begin
            data_o = `ZeroWord;
        end else begin
            data_o = _rom[addr_i[31:2]];
        end
    end

endmodule
