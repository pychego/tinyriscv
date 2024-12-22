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


// core local interruptor module �����жϹ����ٲ�ģ��
module clint (

    input wire clk,
    input wire rst,

    // from if_id ��timer���ж��źŴ��ĵ�����
    input wire [`INT_BUS] int_flag_i,  // �ж������ź� 8bit ��ʱ��timer�ж�����

    // from id
    input wire [    `InstBus] inst_i,      // ָ������ 32bit
    input wire [`InstAddrBus] inst_addr_i, // ָ���ַ 32bit

    // from ex
    input wire jump_flag_i,     // �������źź��ж���ʲô��ϵ
    input wire [`InstAddrBus] jump_addr_i,
    input wire                div_started_i,  // ������ʼ��־,(��ִ�г�������ʱΪ1,��������Ӧͬ���ж�)

    // from ctrl  �������ˮ����ͣ��־
    input wire [`Hold_Flag_Bus] hold_flag_i,  // ��ˮ����ͣ��־(δʹ��)

    // from csr_reg
    input wire [`RegBus] data_i,  // CSR�Ĵ�����������(δʹ��)
    input wire [`RegBus] csr_mtvec,    // mtvec�Ĵ��� Machine Trap Vector ���淢���쳣ʱ��������Ҫ��ת���ĵ�ַ
    input wire [`RegBus] csr_mepc,     // mepc�Ĵ��� Machine Exception PC ��ָ�����쳣��ָ��
    input wire [`RegBus] csr_mstatus,  // mstatus�Ĵ���

    // from csr_reg
    input wire global_int_en_i,  // ȫ���ж�ʹ�ܱ�־

    // to ctrl
    output wire hold_flag_o,  // ��ˮ����ͣ��־

    // to csr_reg
    output reg               we_o,     // дCSR�Ĵ�����־
    output reg [`MemAddrBus] waddr_o,  // дCSR�Ĵ�����ַ
    output reg [`MemAddrBus] raddr_o,  // ��CSR�Ĵ�����ַ, ���û�õ� 
    output reg [    `RegBus] data_o,   // дCSR�Ĵ�������

    // to ex
    output reg [`InstAddrBus] int_addr_o,   // �ж���ڵ�ַ
    output reg                int_assert_o  // �жϱ�־

);


    // �ж�״̬����
    localparam S_INT_IDLE = 4'b0001;
    localparam S_INT_SYNC_ASSERT = 4'b0010;  // Synchronous Interrupt, ͬ���ж�
    localparam S_INT_ASYNC_ASSERT = 4'b0100;  // Asynchronous Interrupt, �첽�ж�
    localparam S_INT_MRET = 4'b1000;  // Machine Mode Exception Return, ����ģʽ�жϷ���

    // дCSR�Ĵ���״̬����
    // mstatus(Machine Status Register) ���ƺͷ�ӳ��������ȫ��״̬
    // mepc(Machine Exception Program Counter) �ڷ����쳣���ж�ʱ���浱ǰָ���ַ
    // mcause(Machine Cause Register) �����쳣���жϵ�ԭ��
    localparam S_CSR_IDLE = 5'b00001;  // ����״̬
    localparam S_CSR_MSTATUS = 5'b00010;  // дmstatus�Ĵ���
    localparam S_CSR_MEPC = 5'b00100;  // дmepc�Ĵ���
    localparam S_CSR_MSTATUS_MRET = 5'b01000;  // дmstatus�Ĵ������жϷ���
    localparam S_CSR_MCAUSE = 5'b10000;  // дmcause�Ĵ���

    reg [         3:0 ] int_state;  // �ж�״̬
    reg [         4:0 ] csr_state;
    reg [`InstAddrBus]  inst_addr;
    reg [        31:0 ] cause;

    // ���յ�timer�ж��ź�֮��ͳ�ˢ������ˮ��,exֱ����ͣ,��ͣ��������,���ٴ�Idle�Ϳ�ʼ�����ж�
    assign hold_flag_o = ((int_state != S_INT_IDLE) | (csr_state != S_CSR_IDLE))? `HoldEnable: `HoldDisable;


    /* int_state �ж��ٲ��߼�(����߼�)  �жϲ�����������!!!
    ͬ���ж� > �첽�ж� > �жϷ���
    ͬ���ж�: ���ִ�н׶ε�ָ��Ϊ����ָ����Ȳ�����ͬ���жϣ��ȳ���ָ��ִ�����ٴ���
    �첽�ж�: ��ʱ���ж�(�����ж�)��ȫ���ж�ʹ��(mstatus[3])��ʱ, �����첽�ж�
    �жϷ���: ��ִ�н׶ε�ָ��ΪMRETʱ, �����жϷ���
    */
    always @(*) begin
        if (rst == `RstEnable) begin
            int_state = S_INT_IDLE;
        end else begin  // ECALL��EBREAK����ͬ���ж�
            if (inst_i == `INST_ECALL || inst_i == `INST_EBREAK) begin
                // ���ִ�н׶ε�ָ��Ϊ����ָ����Ȳ�����ͬ���жϣ��ȳ���ָ��ִ�����ٴ���
                if (div_started_i == `DivStop) begin
                    int_state = S_INT_SYNC_ASSERT;
                end else begin
                    int_state = S_INT_IDLE;
                end
                // �첽�ж�  int_flag_i��timer������
            end else if (int_flag_i != `INT_NONE && global_int_en_i == `True) begin
                int_state = S_INT_ASYNC_ASSERT;
            end else if (inst_i == `INST_MRET) begin  // �жϷ���
                int_state = S_INT_MRET;
            end else begin
                int_state = S_INT_IDLE;
            end
        end
    end

    // дCSR�Ĵ���״̬�л�
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            csr_state <= S_CSR_IDLE;
            cause <= `ZeroWord;
            inst_addr <= `ZeroWord;
        end else begin
            case (csr_state)
                S_CSR_IDLE: begin
                    // ͬ���жϣ� ��ʱ�Ѿ�����ͬ���ж�
                    if (int_state == S_INT_SYNC_ASSERT) begin
                        csr_state <= S_CSR_MEPC;
                        if (jump_flag_i == `JumpEnable) begin   // ͬ���ж�����������������ʲô���? 
                            inst_addr <= jump_addr_i - 4'h4;    // ���� ???
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
                        // �첽�ж�
                    end else if (int_state == S_INT_ASYNC_ASSERT) begin
                        // ��ʱ���ж�
                        cause <= 32'h80000004;
                        csr_state <= S_CSR_MEPC;
                        /*  ��timer_int.c��tinyriscv�ϵķ��沨�ο���֪��, ����timer_int�ź�֮��,����5�����ڲŻ�
                            ������ex��jump_flag_i == `JumpEnable, ����timer���ж����㲻��jump����, ����inst_addr <= inst_addr_i;
                            inst_addr_i������ģ�������,��pc��һ��,�����жϽ���֮����ת��֮ǰ��inst_addr_i��Ϊpcֵ
                        */
                        if (jump_flag_i == `JumpEnable) begin  // timer�жϲ�����jump����
                            inst_addr <= jump_addr_i;
                            // �첽�жϿ����жϳ���ָ���ִ�У��жϴ�����������ִ�г���ָ��
                        end else if (div_started_i == `DivStart) begin
                            inst_addr <= inst_addr_i - 4'h4;    // ������ڽ��г���, ���´����¿�ʼ
                        end else begin
                            inst_addr <= inst_addr_i;   // timer�ж�ֻ������һ��
                        end
                        // �жϷ���
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

    // �����ж��ź�ǰ����д����CSR�Ĵ��� csr_reg
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            we_o <= `WriteDisable;
            waddr_o <= `ZeroWord;
            data_o <= `ZeroWord;
        end else begin
            case (csr_state)
                // ��mepc�Ĵ�����ֵ��Ϊ��ǰָ���ַ
                S_CSR_MEPC: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MEPC};
                    data_o <= inst_addr;
                end
                // д�жϲ�����ԭ��
                S_CSR_MCAUSE: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MCAUSE};
                    data_o <= cause;
                end
                // �ر�ȫ���ж�
                S_CSR_MSTATUS: begin
                    we_o <= `WriteEnable;
                    waddr_o <= {20'h0, `CSR_MSTATUS};
                    data_o <= {csr_mstatus[31:4], 1'b0, csr_mstatus[2:0]};
                end
                // �жϷ���
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

    // �����ж��źŸ�exģ��
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            int_assert_o <= `INT_DEASSERT;
            int_addr_o   <= `ZeroWord;
        end else begin
            case (csr_state)
                // �����жϽ����ź�.д��mcause�Ĵ������ܷ�, �����쳣��תһ��, �����������ת����
                S_CSR_MCAUSE: begin
                    int_assert_o <= `INT_ASSERT;
                    int_addr_o   <= csr_mtvec;  // �쳣��������ַ
                end
                // �����жϷ����ź�
                S_CSR_MSTATUS_MRET: begin
                    int_assert_o <= `INT_ASSERT;
                    int_addr_o   <= csr_mepc;   // �жϷ��ص�ַ
                end
                default: begin
                    int_assert_o <= `INT_DEASSERT;
                    int_addr_o   <= `ZeroWord;
                end
            endcase
        end
    end

endmodule
