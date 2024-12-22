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

`include "defines.v"


// core local interruptor module 核心中断管理、仲裁模块
module clint (

    input wire clk,
    input wire rst,

    // from if_id 将timer的中断信号打拍到这里
    input wire [`INT_BUS] int_flag_i,  // 中断输入信号 8bit 定时器timer中断输入

    // from id
    input wire [    `InstBus] inst_i,      // 指令内容 32bit
    input wire [`InstAddrBus] inst_addr_i, // 指令地址 32bit

    // from ex
    input wire jump_flag_i,     // 这两个信号和中断有什么关系
    input wire [`InstAddrBus] jump_addr_i,
    input wire                div_started_i,  // 除法开始标志,(在执行除法操作时为1,程序不能响应同步中断)

    // from ctrl  整体的流水线暂停标志
    input wire [`Hold_Flag_Bus] hold_flag_i,  // 流水线暂停标志(未使用)

    // from csr_reg
    input wire [`RegBus] data_i,  // CSR寄存器输入数据(未使用)
    input wire [`RegBus] csr_mtvec,    // mtvec寄存器 Machine Trap Vector 保存发生异常时处理器需要跳转到的地址
    input wire [`RegBus] csr_mepc,     // mepc寄存器 Machine Exception PC 它指向发生异常的指令
    input wire [`RegBus] csr_mstatus,  // mstatus寄存器

    // from csr_reg
    input wire global_int_en_i,  // 全局中断使能标志

    // to ctrl
    output wire hold_flag_o,  // 流水线暂停标志

    // to csr_reg
    output reg               we_o,     // 写CSR寄存器标志
    output reg [`MemAddrBus] waddr_o,  // 写CSR寄存器地址
    output reg [`MemAddrBus] raddr_o,  // 读CSR寄存器地址, 这个没用到 
    output reg [    `RegBus] data_o,   // 写CSR寄存器数据

    // to ex
    output reg [`InstAddrBus] int_addr_o,   // 中断入口地址
    output reg                int_assert_o  // 中断标志

);


    // 中断状态定义
    localparam S_INT_IDLE = 4'b0001;
    localparam S_INT_SYNC_ASSERT = 4'b0010;  // Synchronous Interrupt, 同步中断
    localparam S_INT_ASYNC_ASSERT = 4'b0100;  // Asynchronous Interrupt, 异步中断
    localparam S_INT_MRET = 4'b1000;  // Machine Mode Exception Return, 机器模式中断返回

    // 写CSR寄存器状态定义
    // mstatus(Machine Status Register) 控制和反映处理器的全局状态
    // mepc(Machine Exception Program Counter) 在发生异常或中断时保存当前指令地址
    // mcause(Machine Cause Register) 保存异常或中断的原因
    localparam S_CSR_IDLE = 5'b00001;  // 空闲状态
    localparam S_CSR_MSTATUS = 5'b00010;  // 写mstatus寄存器
    localparam S_CSR_MEPC = 5'b00100;  // 写mepc寄存器
    localparam S_CSR_MSTATUS_MRET = 5'b01000;  // 写mstatus寄存器，中断返回
    localparam S_CSR_MCAUSE = 5'b10000;  // 写mcause寄存器

    reg [         3:0 ] int_state;  // 中断状态
    reg [         4:0 ] csr_state;
    reg [`InstAddrBus]  inst_addr;
    reg [        31:0 ] cause;

    // 接收到timer中断信号之后就冲刷整个流水线,ex直接暂停,暂停几个周期,等再次Idle就开始处理中断
    assign hold_flag_o = ((int_state != S_INT_IDLE) | (csr_state != S_CSR_IDLE))? `HoldEnable: `HoldDisable;


    /* int_state 中断仲裁逻辑(组合逻辑)  中断产生最初的起点!!!
    同步中断 > 异步中断 > 中断返回
    同步中断: 如果执行阶段的指令为除法指令，则先不处理同步中断，等除法指令执行完再处理
    异步中断: 定时器中断(外设中断)和全局中断使能(mstatus[3])打开时, 触发异步中断
    中断返回: 当执行阶段的指令为MRET时, 触发中断返回
    */
    always @(*) begin
        if (rst == `RstEnable) begin
            int_state = S_INT_IDLE;
        end else begin  // ECALL和EBREAK产生同步中断
            if (inst_i == `INST_ECALL || inst_i == `INST_EBREAK) begin
                // 如果执行阶段的指令为除法指令，则先不处理同步中断，等除法指令执行完再处理
                if (div_started_i == `DivStop) begin
                    int_state = S_INT_SYNC_ASSERT;
                end else begin
                    int_state = S_INT_IDLE;
                end
                // 异步中断  int_flag_i是timer产生的
            end else if (int_flag_i != `INT_NONE && global_int_en_i == `True) begin
                int_state = S_INT_ASYNC_ASSERT;
            end else if (inst_i == `INST_MRET) begin  // 中断返回
                int_state = S_INT_MRET;
            end else begin
                int_state = S_INT_IDLE;
            end
        end
    end

    // 写CSR寄存器状态切换
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            csr_state <= S_CSR_IDLE;
            cause <= `ZeroWord;
            inst_addr <= `ZeroWord;
        end else begin
            case (csr_state)
                S_CSR_IDLE: begin
                    // 同步中断， 此时已经进入同步中断
                    if (int_state == S_INT_SYNC_ASSERT) begin
                        csr_state <= S_CSR_MEPC;
                        if (jump_flag_i == `JumpEnable) begin   // 同步中断如果满足这个条件是什么情况? 
                            inst_addr <= jump_addr_i - 4'h4;    // 不懂 ???
                        end else begin
                            inst_addr <= inst_addr_i;
                        end
                        case (inst_i)
                            `INST_ECALL: begin
                                cause <= 32'd11;
                            end
                            `INST_EBREAK: begin
                                cause <= 32'd3;
                            end
                            default: begin
                                cause <= 32'd10;
                            end
                        endcase
                        // 异步中断
                    end else if (int_state == S_INT_ASYNC_ASSERT) begin
                        // 定时器中断
                        cause <= 32'h80000004;
                        csr_state <= S_CSR_MEPC;
                        /*  看timer_int.c在tinyriscv上的仿真波形可以知道, 来了timer_int信号之后,过了5个周期才会
                            有来自ex的jump_flag_i == `JumpEnable, 所以timer的中断满足不了jump条件, 所以inst_addr <= inst_addr_i;
                            inst_addr_i是译码模块的输入,比pc慢一拍,所以中断结束之后跳转到之前的inst_addr_i作为pc值
                        */
                        if (jump_flag_i == `JumpEnable) begin  // timer中断不满足jump条件
                            inst_addr <= jump_addr_i;
                            // 异步中断可以中断除法指令的执行，中断处理完再重新执行除法指令
                        end else if (div_started_i == `DivStart) begin
                            inst_addr <= inst_addr_i - 4'h4;    // 如果正在进行除法, 就下次重新开始
                        end else begin
                            inst_addr <= inst_addr_i;   // timer中断只满足这一个
                        end
                        // 中断返回
                    end else if (int_state == S_INT_MRET) begin
                        csr_state <= S_CSR_MSTATUS_MRET;
                    end
                end
                S_CSR_MEPC: begin
                    csr_state <= S_CSR_MSTATUS;
                end
                S_CSR_MSTATUS: begin
                    csr_state <= S_CSR_MCAUSE;
                end
                S_CSR_MCAUSE: begin
                    csr_state <= S_CSR_IDLE;
                end
                S_CSR_MSTATUS_MRET: begin
                    csr_state <= S_CSR_IDLE;
                end
                default: begin
                    csr_state <= S_CSR_IDLE;
                end
            endcase
        end
    end

    // 发出中断信号前，先写几个CSR寄存器 csr_reg
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            we_o <= `WriteDisable;
            waddr_o <= `ZeroWord;
            data_o <= `ZeroWord;
        end else begin
            case (csr_state)
                // 将mepc寄存器的值设为当前指令地址
                S_CSR_MEPC: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MEPC};
                    data_o <= inst_addr;
                end
                // 写中断产生的原因
                S_CSR_MCAUSE: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MCAUSE};
                    data_o <= cause;
                end
                // 关闭全局中断
                S_CSR_MSTATUS: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MSTATUS};
                    data_o <= {csr_mstatus[31:4], 1'b0, csr_mstatus[2:0]};
                end
                // 中断返回
                S_CSR_MSTATUS_MRET: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MSTATUS};
                    data_o <= {csr_mstatus[31:4], csr_mstatus[7], csr_mstatus[2:0]};
                end
                default: begin
                    we_o <= `WriteDisable;
                    waddr_o <= `ZeroWord;
                    data_o <= `ZeroWord;
                end
            endcase
        end
    end

    // 发出中断信号给ex模块
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            int_assert_o <= `INT_DEASSERT;
            int_addr_o   <= `ZeroWord;
        end else begin
            case (csr_state)
                // 发出中断进入信号.写完mcause寄存器才能发, 处理异常跳转一次, 处理结束后跳转回来
                S_CSR_MCAUSE: begin
                    int_assert_o <= `INT_ASSERT;
                    int_addr_o   <= csr_mtvec;  // 异常处理函数地址
                end
                // 发出中断返回信号
                S_CSR_MSTATUS_MRET: begin
                    int_assert_o <= `INT_ASSERT;
                    int_addr_o   <= csr_mepc;   // 中断返回地址
                end
                default: begin
                    int_assert_o <= `INT_DEASSERT;
                    int_addr_o   <= `ZeroWord;
                end
            endcase
        end
    end

endmodule
