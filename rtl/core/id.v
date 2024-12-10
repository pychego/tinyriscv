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

// 译码模块
// 纯组合逻辑电路
module id (

    input wire rst,

    // from if_id
    input wire [    `InstBus] inst_i,      // 指令内容
    input wire [`InstAddrBus] inst_addr_i, // 指令地址

    // from regs
    input wire [`RegBus] reg1_rdata_i,  // 通用寄存器1输入数据  
    input wire [`RegBus] reg2_rdata_i,  // 通用寄存器2输入数据

    // from csr reg "Control and Status Registers"，即控制和状态寄存器
    input wire [`RegBus] csr_rdata_i,  // CSR寄存器输入数据,来自csr_reg模块

    // from ex
    input wire ex_jump_flag_i,  // 跳转标志,这个没用到呀

    // to regs
    output reg [`RegAddrBus] reg1_raddr_o,  // 读通用寄存器1地址, 实时得到reg1_rdata_i
    output reg [`RegAddrBus] reg2_raddr_o,  // 读通用寄存器2地址, 实时得到reg2_rdata_i

    // to csr reg
    output reg [`MemAddrBus] csr_raddr_o,  // 读CSR寄存器地址

    // to ex
    output reg [`MemAddrBus] op1_o,  // 操作数1
    output reg [`MemAddrBus] op2_o,  // 操作数2
    output reg [`MemAddrBus] op1_jump_o,
    output reg [`MemAddrBus] op2_jump_o,
    output reg [`InstBus] inst_o,  // 指令内容
    output reg [`InstAddrBus] inst_addr_o,  // 指令地址
    output reg [`RegBus] reg1_rdata_o,  // 通用寄存器1数据, 不打拍直接送到id_ex模块
    output reg [`RegBus] reg2_rdata_o,  // 通用寄存器2数据
    output reg reg_we_o,  // 写通用寄存器标志
    output reg [`RegAddrBus] reg_waddr_o,  // 写通用寄存器地址
    output reg csr_we_o,  // 写CSR寄存器标志, 送到id_ex模块
    output reg [`RegBus] csr_rdata_o,  // CSR寄存器数据, 送到id_ex模块
    output reg [`MemAddrBus] csr_waddr_o  // 写CSR寄存器地址, 送到id_ex模块

);

    // 此处对照riscv指令集手册即可 R-type对应的上
    wire [6:0] opcode = inst_i[6:0];
    wire [2:0] funct3 = inst_i[14:12];
    wire [6:0] funct7 = inst_i[31:25];
    wire [4:0] rd = inst_i[11:7];  // 目的寄存器地址
    wire [4:0] rs1 = inst_i[19:15];  // 源寄存器1地址
    wire [4:0] rs2 = inst_i[24:20];  // 源寄存器2地址


    always @(*) begin
        inst_o = inst_i;
        inst_addr_o = inst_addr_i;
        reg1_rdata_o = reg1_rdata_i;
        reg2_rdata_o = reg2_rdata_i;
        csr_rdata_o = csr_rdata_i;
        csr_raddr_o = `ZeroWord;
        csr_waddr_o = `ZeroWord;
        csr_we_o = `WriteDisable;
        op1_o = `ZeroWord;
        op2_o = `ZeroWord;
        op1_jump_o = `ZeroWord;
        op2_jump_o = `ZeroWord;

        case (opcode)
            `INST_TYPE_I: begin  // 立即数指令
                case (funct3)
                    `INST_ADDI, `INST_SLTI, `INST_SLTIU, `INST_XORI, `INST_ORI, `INST_ANDI, `INST_SLLI, `INST_SRI: begin
                        reg_we_o = `WriteEnable;
                        reg_waddr_o = rd;
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = `ZeroReg;
                        op1_o = reg1_rdata_i;
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]};
                    end
                    default: begin
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                        reg1_raddr_o = `ZeroReg;
                        reg2_raddr_o = `ZeroReg;
                    end
                endcase
            end
            `INST_TYPE_R_M: begin  // R-type指令 以及 M-type指令
                if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin  // 简单运算
                    case (funct3)
                        `INST_ADD_SUB, `INST_SLL, `INST_SLT, `INST_SLTU, `INST_XOR, `INST_SR, `INST_OR, `INST_AND: begin
                            reg_we_o = `WriteEnable;
                            reg_waddr_o = rd;
                            reg1_raddr_o = rs1;
                            reg2_raddr_o = rs2;
                            op1_o = reg1_rdata_i;
                            op2_o = reg2_rdata_i;
                        end
                        default: begin
                            reg_we_o = `WriteDisable;
                            reg_waddr_o = `ZeroReg;
                            reg1_raddr_o = `ZeroReg;
                            reg2_raddr_o = `ZeroReg;
                        end
                    endcase
                end else if (funct7 == 7'b0000001) begin  // M-type指令 乘法和除法
                    case (funct3)
                        `INST_MUL, `INST_MULHU, `INST_MULH, `INST_MULHSU: begin
                            reg_we_o = `WriteEnable;
                            reg_waddr_o = rd;
                            reg1_raddr_o = rs1;
                            reg2_raddr_o = rs2;
                            op1_o = reg1_rdata_i;
                            op2_o = reg2_rdata_i;
                        end
                        `INST_DIV, `INST_DIVU, `INST_REM, `INST_REMU: begin
                            reg_we_o = `WriteDisable;
                            reg_waddr_o = rd;
                            reg1_raddr_o = rs1;
                            reg2_raddr_o = rs2;
                            op1_o = reg1_rdata_i;
                            op2_o = reg2_rdata_i;
                            op1_jump_o = inst_addr_i;
                            op2_jump_o = 32'h4;
                        end
                        default: begin
                            reg_we_o = `WriteDisable;
                            reg_waddr_o = `ZeroReg;
                            reg1_raddr_o = `ZeroReg;
                            reg2_raddr_o = `ZeroReg;
                        end
                    endcase
                end else begin
                    reg_we_o = `WriteDisable;
                    reg_waddr_o = `ZeroReg;
                    reg1_raddr_o = `ZeroReg;
                    reg2_raddr_o = `ZeroReg;
                end
            end
            `INST_TYPE_L: begin  // 内存访问指令, 只用到源寄存器1 Load
                case (funct3)
                    `INST_LB, `INST_LH, `INST_LW, `INST_LBU, `INST_LHU: begin
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = `ZeroReg;
                        reg_we_o = `WriteEnable;
                        reg_waddr_o = rd;
                        op1_o = reg1_rdata_i;  // 这里预先计算访存的地址
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]};
                    end
                    default: begin
                        reg1_raddr_o = `ZeroReg;
                        reg2_raddr_o = `ZeroReg;
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                    end
                endcase
            end
            `INST_TYPE_S: begin  // 内存访问指令 Store
                case (funct3)
                    `INST_SB, `INST_SW, `INST_SH: begin
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = rs2;
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                        op1_o = reg1_rdata_i;
                        op2_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
                    end
                    default: begin
                        reg1_raddr_o = `ZeroReg;
                        reg2_raddr_o = `ZeroReg;
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                    end
                endcase
            end
            `INST_TYPE_B: begin  // 分支指令 有条件跳转
                case (funct3)
                    `INST_BEQ, `INST_BNE, `INST_BLT, `INST_BGE, `INST_BLTU, `INST_BGEU: begin
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = rs2;
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                        op1_o = reg1_rdata_i;
                        op2_o = reg2_rdata_i;
                        // 这里只是把ex.v中的跳转地址进行提前计算了  lyb
                        op1_jump_o = inst_addr_i; // pc_o
                        op2_jump_o = {
                            {20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0
                        };
                    end
                    default: begin
                        reg1_raddr_o = `ZeroReg;
                        reg2_raddr_o = `ZeroReg;
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                    end
                endcase
            end
            `INST_JAL: begin        // Jump and Link
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
                op1_o = inst_addr_i;
                op2_o = 32'h4;
                op1_jump_o = inst_addr_i;
                op2_jump_o = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
            end
            `INST_JALR: begin   // Jump and Link Register
                reg_we_o = `WriteEnable;
                reg1_raddr_o = rs1;
                reg2_raddr_o = `ZeroReg;
                reg_waddr_o = rd;
                op1_o = inst_addr_i;
                op2_o = 32'h4;
                op1_jump_o = reg1_rdata_i;
                op2_jump_o = {{20{inst_i[31]}}, inst_i[31:20]};
            end
            `INST_LUI: begin  // 高位立即数加载 Load Upper Immediate
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
                op1_o = {inst_i[31:12], 12'b0};
                op2_o = `ZeroWord;
            end
            `INST_AUIPC: begin  // PC加立即数 Add Upper Immediate to PC
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
                op1_o = inst_addr_i;
                op2_o = {inst_i[31:12], 12'b0};
            end
            `INST_NOP_OP: begin  // 空操作 No Operation
                reg_we_o = `WriteDisable;
                reg_waddr_o = `ZeroReg;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
            end
            `INST_FENCE: begin  // 不太懂这个
                reg_we_o = `WriteDisable;
                reg_waddr_o = `ZeroReg;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
                op1_jump_o = inst_addr_i;
                op2_jump_o = 32'h4;
            end
            `INST_CSR: begin   // 控制和状态寄存器指令
                reg_we_o = `WriteDisable;
                reg_waddr_o = `ZeroReg;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
                csr_raddr_o = {20'h0, inst_i[31:20]};
                csr_waddr_o = {20'h0, inst_i[31:20]};
                case (funct3)
                    `INST_CSRRW, `INST_CSRRS, `INST_CSRRC: begin
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = `ZeroReg;
                        reg_we_o = `WriteEnable;
                        reg_waddr_o = rd;
                        csr_we_o = `WriteEnable;
                    end
                    `INST_CSRRWI, `INST_CSRRSI, `INST_CSRRCI: begin
                        reg1_raddr_o = `ZeroReg;
                        reg2_raddr_o = `ZeroReg;
                        reg_we_o = `WriteEnable;
                        reg_waddr_o = rd;
                        csr_we_o = `WriteEnable;
                    end
                    default: begin
                        reg_we_o = `WriteDisable;
                        reg_waddr_o = `ZeroReg;
                        reg1_raddr_o = `ZeroReg;
                        reg2_raddr_o = `ZeroReg;
                        csr_we_o = `WriteDisable;
                    end
                endcase
            end
            default: begin
                reg_we_o = `WriteDisable;
                reg_waddr_o = `ZeroReg;
                reg1_raddr_o = `ZeroReg;
                reg2_raddr_o = `ZeroReg;
            end
        endcase
    end

endmodule
