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

/* 通用寄存器模块, 32个通用寄存器x0~x31, PC寄存器不在其中
    regs模块接收id译码模块的rs1和rs2地址, 直接输出rs1和rs2的数据给id译码模块
*/
// 读寄存器1和读寄存器2的数据输出到译码模块id,没有
module regs (

    input wire clk,
    input wire rst,

    // from ex(执行)
    input wire               we_i,     // 写寄存器标志
    input wire [`RegAddrBus] waddr_i,  // 写寄存器地址 RegAddrBus 4:0
    input wire [    `RegBus] wdata_i,  // 写寄存器数据 RegBus 31:0

    // from jtag
    input wire               jtag_we_i,    // 写寄存器标志
    input wire [`RegAddrBus] jtag_addr_i,  // 读、写寄存器地址
    input wire [    `RegBus] jtag_data_i,  // 写寄存器数据

    // from id(译码)
    input wire [`RegAddrBus] raddr1_i,  // 读寄存器1地址

    // to id
    output reg [`RegBus] rdata1_o,  // 读寄存器1数据

    // from id
    input wire [`RegAddrBus] raddr2_i,  // 读寄存器2地址

    // to id
    output reg [`RegBus] rdata2_o,  // 读寄存器2数据

    // to jtag
    output reg [`RegBus] jtag_data_o  // 读寄存器数据

);

    // 32个通用寄存器  RegNum 32  RegBus 31:0
    reg [`RegBus] regs[0:`RegNum - 1];

    // 写通用寄存器, x0寄存器硬连线为0
    always @(posedge clk) begin
        if (rst == `RstDisable) begin
            // 优先ex模块写操作
            if ((we_i == `WriteEnable) && (waddr_i != `ZeroReg)) begin
                regs[waddr_i] <= wdata_i;
            end else if ((jtag_we_i == `WriteEnable) && (jtag_addr_i != `ZeroReg)) begin
                regs[jtag_addr_i] <= jtag_data_i;
            end
        end
    end

    // 读寄存器1
    always @(*) begin
        if (raddr1_i == `ZeroReg) begin
            rdata1_o = `ZeroWord;
            // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
        end else if (raddr1_i == waddr_i && we_i == `WriteEnable) begin
            rdata1_o = wdata_i;
        end else begin
            rdata1_o = regs[raddr1_i];
        end
    end

    // 读寄存器2
    always @(*) begin
        if (raddr2_i == `ZeroReg) begin
            rdata2_o = `ZeroWord;
            // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
        end else if (raddr2_i == waddr_i && we_i == `WriteEnable) begin
            rdata2_o = wdata_i;
        end else begin
            rdata2_o = regs[raddr2_i];
        end
    end

    // jtag读寄存器
    always @(*) begin
        if (jtag_addr_i == `ZeroReg) begin
            jtag_data_o = `ZeroWord;
        end else begin
            jtag_data_o = regs[jtag_addr_i];
        end
    end

endmodule
