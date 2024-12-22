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

// 执行模块
// 纯组合逻辑电路
module ex (

    input wire rst,

    // from id_ex
    input wire [    `InstBus] inst_i,        // 指令内容
    input wire [`InstAddrBus] inst_addr_i,   // 指令地址, 落后于pc_o两个clk
    input wire                reg_we_i,      // 是否写通用寄存器rd
    input wire [ `RegAddrBus] reg_waddr_i,   // 写通用寄存器地址
    // 主要是id模块根据inst直接向reg访问得到的rs1和rs2中存放的数据
    input wire [     `RegBus] reg1_rdata_i,  // 通用寄存器1输入数据
    input wire [     `RegBus] reg2_rdata_i,  // 通用寄存器2输入数据
    input wire                csr_we_i,      // 是否写CSR寄存器
    input wire [ `MemAddrBus] csr_waddr_i,   // 写CSR寄存器地址
    // 这个是id根据inst从csr_reg中读取的,然后id再送给ex
    input wire [     `RegBus] csr_rdata_i,   // CSR寄存器输入数据
    input wire [ `MemAddrBus] op1_i,
    input wire [ `MemAddrBus] op2_i,
    input wire [ `MemAddrBus] op1_jump_i,
    input wire [ `MemAddrBus] op2_jump_i,

    // from clint
    input wire                int_assert_i,  // 中断发生标志
    input wire [`InstAddrBus] int_addr_i,    // 中断跳转地址

    // from mem, ex作为RIB的Master0, 从mem读取数据
    input wire [`MemBus] mem_rdata_i,  // 内存输入数据

    // from div
    input wire               div_ready_i,     // 除法运算完成标志
    input wire [    `RegBus] div_result_i,    // 除法运算结果
    input wire               div_busy_i,      // 除法运算忙标志
    input wire [`RegAddrBus] div_reg_waddr_i, // 除法运算结束后要写的寄存器地址

    // to mem
    /* 当与RIB总线连接时, 会根据we信号选择addr是mem_raddr_o
    */
    output reg  [    `MemBus] mem_wdata_o,  // 写内存数据
    output reg  [`MemAddrBus] mem_raddr_o,  // 读内存地址
    output reg  [`MemAddrBus] mem_waddr_o,  // 写内存地址
    output wire               mem_we_o,     // 是否要写内存
    output wire               mem_req_o,    // 请求访问内存标志

    // to regs
    output wire [    `RegBus] reg_wdata_o,  // 写寄存器数据
    output wire               reg_we_o,     // 是否要写通用寄存器
    output wire [`RegAddrBus] reg_waddr_o,  // 写通用寄存器地址

    // to csr_reg
    output reg  [    `RegBus] csr_wdata_o,  // 写CSR寄存器数据
    output wire               csr_we_o,     // 是否要写CSR寄存器
    output wire [`MemAddrBus] csr_waddr_o,  // 写CSR寄存器地址

    // to div
    output wire               div_start_o,     // 开始除法运算标志
    output reg  [    `RegBus] div_dividend_o,  // 被除数
    output reg  [    `RegBus] div_divisor_o,   // 除数
    output reg  [        2:0] div_op_o,        // 具体是哪一条除法指令
    output reg  [`RegAddrBus] div_reg_waddr_o, // 除法运算结束后要写的寄存器地址

    // to ctrl 和 clint  timer中断主要是送入clint模块, div导致的暂停主要是送入ctrl模块
    output wire                hold_flag_o,  // 是否暂停标志
    output wire                jump_flag_o,  // 是否跳转标志  to clint, ctrl,  id(未使用)
    output wire [`InstAddrBus] jump_addr_o   // 跳转目的地址  to clint, ctrl

);

    wire [          1:0 ] mem_raddr_index;
    wire [          1:0 ] mem_waddr_index;
    wire [`DoubleRegBus]  mul_temp;
    wire [`DoubleRegBus]  mul_temp_invert;
    wire [         31:0 ] sr_shift;
    wire [         31:0 ] sri_shift;
    wire [         31:0 ] sr_shift_mask;
    wire [         31:0 ] sri_shift_mask;
    wire [         31:0 ] op1_add_op2_res;
    wire [         31:0 ] op1_jump_add_op2_jump_res;
    wire [         31:0 ] reg1_data_invert;
    wire [         31:0 ] reg2_data_invert;
    wire                  op1_ge_op2_signed;
    wire                  op1_ge_op2_unsigned;
    wire                  op1_eq_op2;
    reg  [      `RegBus]  mul_op1;
    reg  [      `RegBus]  mul_op2;
    wire [          6:0 ] opcode;
    wire [          2:0 ] funct3;
    wire [          6:0 ] funct7;
    wire [          4:0 ] rd;
    wire [          4:0 ] uimm;
    reg  [      `RegBus]  reg_wdata;
    reg                   reg_we;
    reg  [  `RegAddrBus]  reg_waddr;
    reg  [      `RegBus]  div_wdata;
    reg                   div_we;
    reg  [  `RegAddrBus]  div_waddr;
    reg                   div_hold_flag;
    reg                   div_jump_flag;
    reg  [ `InstAddrBus]  div_jump_addr;
    reg                   hold_flag;
    reg                   jump_flag;        // 是一般指令中的跳转标志
    reg  [ `InstAddrBus]  jump_addr;
    reg                   mem_we;
    reg                   mem_req;
    reg                   div_start;

    assign opcode = inst_i[6:0];
    assign funct3 = inst_i[14:12];
    assign funct7 = inst_i[31:25];
    assign rd = inst_i[11:7];
    assign uimm = inst_i[19:15];  // Unsigned immediate 无符号立即数

    /* 逻辑右移: >>  算术右移: >>>
       这几句都是为了下面算术右移做准备的
       sr_shift: 逻辑右移,x[rs2]的低5位是移位数, 高位则被忽略
       sri_shift: 立即数逻辑右移
    */
    assign sr_shift = reg1_rdata_i >> reg2_rdata_i[4:0];
    assign sri_shift = reg1_rdata_i >> inst_i[24:20];
    assign sr_shift_mask = 32'hffffffff >> reg2_rdata_i[4:0];
    assign sri_shift_mask = 32'hffffffff >> inst_i[24:20];

    /* 计算操作数的加法结果, 用于ADDI, ADD, SUB, SLT, SLTU, XOR, OR, AND指令
       op1_add_op2_res: op1_i + op2_i
       op1_jump_add_op2_jump_res: op1_jump_i + op2_jump_i
       op1_i, op2_i, op1_jump_i, op2_jump_i 在id模块中预算了
    */
    assign op1_add_op2_res = op1_i + op2_i;
    assign op1_jump_add_op2_jump_res = op1_jump_i + op2_jump_i;

    /* 不太懂这两个是干嘛的
       reg1_data_invert: reg1_rdata_i取反加1
       reg2_data_invert: reg2_rdata_i取反加1
    */
    assign reg1_data_invert = ~reg1_rdata_i + 1;
    assign reg2_data_invert = ~reg2_rdata_i + 1;

    // 有符号数比较
    assign op1_ge_op2_signed = $signed(op1_i) >= $signed(op2_i);
    // 无符号数比较
    assign op1_ge_op2_unsigned = op1_i >= op2_i;
    assign op1_eq_op2 = (op1_i == op2_i);

    assign mul_temp = mul_op1 * mul_op2;
    assign mul_temp_invert = ~mul_temp + 1;  // 存放的是最终补码

    // mem_raddr_index是取了mem_raddr_o的低两位
    /* 这里是L-type指令, 从内存读取数据
       mem_raddr_index: 读内存地址的低两位 
       mem_waddr_index: 写内存地址的低两位
       reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:20]} 就是要读的读内存地址, 具体代码在id中
    */
    assign mem_raddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:20]}) & 2'b11;
    assign mem_waddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}) & 2'b11;

    assign div_start_o = (int_assert_i == `INT_ASSERT) ? `DivStop : div_start;

    // ? ? ?  reg_wdata是访问内存得到的数据,要写到rd寄存器中
    assign reg_wdata_o = reg_wdata | div_wdata;
    // 响应中断时不写通用寄存器
    assign reg_we_o = (int_assert_i == `INT_ASSERT) ? `WriteDisable : (reg_we || div_we);
    assign reg_waddr_o = reg_waddr | div_waddr;

    // 响应中断时不写内存
    assign mem_we_o = (int_assert_i == `INT_ASSERT) ? `WriteDisable : mem_we;

    // 响应中断时不向总线请求访问内存
    assign mem_req_o = (int_assert_i == `INT_ASSERT) ? `RIB_NREQ : mem_req;

    /* 这里面的hold_flag在该程序中一直是0
       识别到除法指令之后, 就直接暂停整条流水线
    */
    assign hold_flag_o = hold_flag || div_hold_flag;
    assign jump_flag_o = jump_flag || div_jump_flag || ((int_assert_i == `INT_ASSERT)? `JumpEnable: `JumpDisable);
    assign jump_addr_o = (int_assert_i == `INT_ASSERT) ? int_addr_i : (jump_addr | div_jump_addr);

    // 响应中断时不写CSR寄存器
    assign csr_we_o = (int_assert_i == `INT_ASSERT) ? `WriteDisable : csr_we_i;
    assign csr_waddr_o = csr_waddr_i;


    // 处理乘法操作数  M-type 乘法和除法
    always @(*) begin
        if ((opcode == `INST_TYPE_R_M) && (funct7 == 7'b0000001)) begin
            case (funct3)
                `INST_MUL, `INST_MULHU: begin
                    mul_op1 = reg1_rdata_i;
                    mul_op2 = reg2_rdata_i;
                end
                `INST_MULHSU: begin  // 高位有符号-无符号乘(Multiply High Signed-Unsigned).
                    // 将x[rs1]视为2的补码 x[rs2]视为无符号数
                    mul_op1 = (reg1_rdata_i[31] == 1'b1) ? (reg1_data_invert) : reg1_rdata_i;
                    mul_op2 = reg2_rdata_i;
                end
                `INST_MULH: begin
                    mul_op1 = (reg1_rdata_i[31] == 1'b1) ? (reg1_data_invert) : reg1_rdata_i;
                    mul_op2 = (reg2_rdata_i[31] == 1'b1) ? (reg2_data_invert) : reg2_rdata_i;
                end
                default: begin
                    mul_op1 = reg1_rdata_i;
                    mul_op2 = reg2_rdata_i;
                end
            endcase
        end else begin
            mul_op1 = reg1_rdata_i;
            mul_op2 = reg2_rdata_i;
        end
    end

    // 处理除法指令
    always @(*) begin
        div_dividend_o = reg1_rdata_i;
        div_divisor_o = reg2_rdata_i;
        div_op_o = funct3;
        div_reg_waddr_o = reg_waddr_i;
        if ((opcode == `INST_TYPE_R_M) && (funct7 == 7'b0000001)) begin
            div_we = `WriteDisable;
            div_wdata = `ZeroWord;
            div_waddr = `ZeroWord;
            case (funct3)
                `INST_DIV, `INST_DIVU, `INST_REM, `INST_REMU: begin
                    div_start = `DivStart;  // 识别到除法指令,开始除法运算
                    div_jump_flag = `JumpEnable;
                    div_hold_flag = `HoldEnable;
                    div_jump_addr = op1_jump_add_op2_jump_res;
                end
                default: begin
                    div_start = `DivStop;
                    div_jump_flag = `JumpDisable;
                    div_hold_flag = `HoldDisable;
                    div_jump_addr = `ZeroWord;
                end
            endcase
        end else begin
            div_jump_flag = `JumpDisable;
            div_jump_addr = `ZeroWord;
            if (div_busy_i == `True) begin
                div_start = `DivStart;
                div_we = `WriteDisable;
                div_wdata = `ZeroWord;
                div_waddr = `ZeroWord;
                div_hold_flag = `HoldEnable;
            end else begin
                div_start     = `DivStop;
                div_hold_flag = `HoldDisable;  // 除法运算结束,恢复流水线
                /* ox10为div指令的地址pc_o
                除法开始...
                   clk0到来, pc_o为0x10, 译码id为0x0C, ex执行0x08
                   clk1到来, pc_o为0x14, 译码id为0x10,译出div指令, ex执行0x0C
                   clk2到来, pc_o为0x18, 译码id为0x14, ex执行0x10,输出流水线暂停指令给ctrl, 并输出跳转使能和跳转地址
                   clk3的到来,pc_o根据跳转地址跳转到0x10 + 0x04 = 0x14, 译码停止, ex停止
                除法结束...
                   clk0到来,除法结束,这个周期pc_o还是0x14,但是译码id空档,ex执行空档
                   clk1到来,pc_o为0x18,译码id为0x14,ex执行空档!!!
                   clk2到来, pc_o为0x1c, 译码id为0x18, ex执行0x14
                */
                if (div_ready_i == `DivResultReady) begin
                    div_wdata = div_result_i;
                    div_waddr = div_reg_waddr_i;
                    div_we = `WriteEnable;
                end else begin
                    div_we = `WriteDisable;
                    div_wdata = `ZeroWord;
                    div_waddr = `ZeroWord;
                end
            end
        end
    end

    // 执行
    always @(*) begin
        reg_we = reg_we_i;
        reg_waddr = reg_waddr_i;
        mem_req = `RIB_NREQ;
        csr_wdata_o = `ZeroWord;

        case (opcode)
            `INST_TYPE_I: begin
                case (funct3)
                    `INST_ADDI: begin  // 首先对当前指令不涉及到的操作置回默认值
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_add_op2_res;
                    end
                    `INST_SLTI: begin  // 小于立即数则置位(Set if Less Than Immediate)
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1;
                    end
                    `INST_SLTIU: begin  // 无符号小于立即数则置位(Set if Less Than Immediate, Unsigned)
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1;
                    end
                    `INST_XORI: begin  // x[rd] = x[rs1] ^ sext(immediate)
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i ^ op2_i;
                    end
                    `INST_ORI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i | op2_i;
                    end
                    `INST_ANDI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i & op2_i;
                    end
                    `INST_SLLI: begin  // 立即数逻辑左移(Shift Left Logical Immediate).
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = reg1_rdata_i << inst_i[24:20];
                    end
                    `INST_SRI: begin  // 立即数右移
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        if (inst_i[30] == 1'b1) begin  //  // 算术右移, 逻辑有点麻烦, 举个例子可以明白
                            reg_wdata = (sri_shift & sri_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sri_shift_mask));
                        end else begin
                            reg_wdata = reg1_rdata_i >> inst_i[24:20];
                        end
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_R_M: begin
                if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin
                    case (funct3)
                        `INST_ADD_SUB: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            if (inst_i[30] == 1'b0) begin  // ADD
                                reg_wdata = op1_add_op2_res;
                            end else begin  // SUB
                                reg_wdata = op1_i - op2_i;
                            end
                        end
                        `INST_SLL: begin  // 逻辑左移  (Shift Left Logical)
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i << op2_i[4:0];
                        end
                        `INST_SLT: begin  // x[rd] = (x[rs1] <𝑠 x[rs2])
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1;
                        end
                        `INST_SLTU: begin  // x[rd] = (x[rs1] <𝑢 sext(immediate))
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1;
                        end
                        `INST_XOR: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i ^ op2_i;
                        end
                        `INST_SR: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            if (inst_i[30] == 1'b1) begin   // 算术右移, 逻辑有点麻烦, 举个例子可以明白
                                reg_wdata = (sr_shift & sr_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sr_shift_mask));
                            end else begin  // 逻辑右移
                                reg_wdata = reg1_rdata_i >> reg2_rdata_i[4:0];
                            end
                        end
                        `INST_OR: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i | op2_i;
                        end
                        `INST_AND: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i & op2_i;
                        end
                        default: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = `ZeroWord;
                        end
                    endcase
                end else if (funct7 == 7'b0000001) begin
                    case (funct3)
                        `INST_MUL: begin  // x[rd] = x[rs1] × x[rs2], 忽略算术溢出
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = mul_temp[31:0];
                        end
                        `INST_MULHU: begin  // x[rd] = (x[rs1] 𝑢 ×𝑢 x[rs2]) ≫𝑢 XLEN
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = mul_temp[63:32];
                        end
                        `INST_MULH: begin  // x[rd] = (x[rs1] 𝑠 ×𝑠 x[rs2]) ≫𝑠 XLEN
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            case ({
                                reg1_rdata_i[31], reg2_rdata_i[31]
                            })
                                2'b00: begin
                                    reg_wdata = mul_temp[63:32];
                                end
                                2'b11: begin  // 两个数都是负数, 前面已经处理过了mul_op1和mul_op2
                                    reg_wdata = mul_temp[63:32];
                                end
                                2'b10: begin // 直接看不好理解, 使用8位数试一下即可 -5 * 3
                                    reg_wdata = mul_temp_invert[63:32];
                                end
                                default: begin
                                    reg_wdata = mul_temp_invert[63:32];
                                end
                            endcase
                        end
                        `INST_MULHSU: begin  // x[rd] = (x[rs1] 𝑠 ×𝑢 x[rs2]) ≫𝑠 XLEN
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            if (reg1_rdata_i[31] == 1'b1) begin
                                reg_wdata = mul_temp_invert[63:32];
                            end else begin
                                reg_wdata = mul_temp[63:32];
                            end
                        end
                        default: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata_o = `ZeroWord;
                            mem_raddr_o = `ZeroWord;
                            mem_waddr_o = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = `ZeroWord;
                        end
                    endcase
                end else begin
                    jump_flag = `JumpDisable;
                    hold_flag = `HoldDisable;
                    jump_addr = `ZeroWord;
                    mem_wdata_o = `ZeroWord;
                    mem_raddr_o = `ZeroWord;
                    mem_waddr_o = `ZeroWord;
                    mem_we = `WriteDisable;
                    reg_wdata = `ZeroWord;
                end
            end
            `INST_TYPE_L: begin
                case (funct3)
                    `INST_LB: begin   // x[rd] = sext(M[x[rs1] + sext(offset)][7:0]) 从内存读取一个字节
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: begin
                                reg_wdata = {{24{mem_rdata_i[7]}}, mem_rdata_i[7:0]};
                            end
                            2'b01: begin
                                reg_wdata = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
                            end
                            2'b10: begin
                                reg_wdata = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
                            end
                            default: begin
                                reg_wdata = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
                            end
                        endcase
                    end
                    // x[rd] = sext(M[x[rs1] + sext(offset)][15:0]) 半字加载 (Load Halfword)
                    `INST_LH: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;  // Master0请求总线访问内存
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_raddr_index == 2'b0) begin
                            reg_wdata = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
                        end else begin
                            reg_wdata = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};
                        end
                    end
                    `INST_LW: begin  // x[rd] = sext(M[x[rs1] + sext(offset)][31:0])
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        reg_wdata = mem_rdata_i;  // 请求总线,接收内存数据都是组合逻辑
                    end
                    `INST_LBU: begin  // x[rd] = M[x[rs1] + sext(offset)][7:0]
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: begin
                                reg_wdata = {24'h0, mem_rdata_i[7:0]};
                            end
                            2'b01: begin
                                reg_wdata = {24'h0, mem_rdata_i[15:8]};
                            end
                            2'b10: begin
                                reg_wdata = {24'h0, mem_rdata_i[23:16]};
                            end
                            default: begin
                                reg_wdata = {24'h0, mem_rdata_i[31:24]};
                            end
                        endcase
                    end
                    `INST_LHU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_raddr_index == 2'b0) begin
                            reg_wdata = {16'h0, mem_rdata_i[15:0]};
                        end else begin
                            reg_wdata = {16'h0, mem_rdata_i[31:16]};
                        end
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_S: begin
                case (funct3)
                    `INST_SB: begin  // M[x[rs1] + sext(offset) = x[rs2][7: 0]
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        // Store Byte改变读出来的32位内存数据中对应的字节,其他三个字节的数据保持不变
                        case (mem_waddr_index)
                            2'b00: begin
                                mem_wdata_o = {mem_rdata_i[31:8], reg2_rdata_i[7:0]};
                            end
                            2'b01: begin
                                mem_wdata_o = {
                                    mem_rdata_i[31:16], reg2_rdata_i[7:0], mem_rdata_i[7:0]
                                };
                            end
                            2'b10: begin
                                mem_wdata_o = {
                                    mem_rdata_i[31:24], reg2_rdata_i[7:0], mem_rdata_i[15:0]
                                };
                            end
                            default: begin
                                mem_wdata_o = {reg2_rdata_i[7:0], mem_rdata_i[23:0]};
                            end
                        endcase
                    end
                    `INST_SH: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_waddr_index == 2'b00) begin
                            mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[15:0]};
                        end else begin
                            mem_wdata_o = {reg2_rdata_i[15:0], mem_rdata_i[15:0]};
                        end
                    end
                    `INST_SW: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        mem_wdata_o = reg2_rdata_i;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_B: begin
                case (funct3)
                    // 相等时分支 (Branch if Equal)
                    `INST_BEQ: begin  // if (rs1 == rs2) pc += sext(offset)
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = op1_eq_op2 & `JumpEnable;
                        jump_addr = {32{op1_eq_op2}} & op1_jump_add_op2_jump_res;
                    end
                    // 不相等时分支 (Branch if Not Equal).
                    `INST_BNE: begin  // if (rs1 ≠ rs2) pc += sext(offset)
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_eq_op2) & `JumpEnable;
                        jump_addr = {32{(~op1_eq_op2)}} & op1_jump_add_op2_jump_res;
                    end
                    // 小于时分支 (Branch if Less Than)
                    `INST_BLT: begin  // if (rs1 <s rs2) pc += sext(offset)
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_ge_op2_signed) & `JumpEnable;
                        jump_addr = {32{(~op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res;
                    end
                    // 大于等于时分支 (Branch if Greater Than or Equal)
                    `INST_BGE: begin  // if (rs1 ≥s rs2) pc += sext(offset)
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (op1_ge_op2_signed) & `JumpEnable;
                        jump_addr = {32{(op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res;
                    end
                    // 无符号小于时分支 (Branch if Less Than, Unsigned)
                    `INST_BLTU: begin  // if (rs1 <u rs2) pc += sext(offset)
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_ge_op2_unsigned) & `JumpEnable;
                        jump_addr = {32{(~op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res;
                    end
                    // 无符号大于等于时分支 (Branch if Greater Than or Equal, Unsigned)
                    `INST_BGEU: begin  // if (rs1 ≥u rs2) pc += sext(offset)
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (op1_ge_op2_unsigned) & `JumpEnable;
                        jump_addr = {32{(op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            /* JAL: 跳转并链接 (Jump and Link) x[rd] = pc+4; pc += sext(offset)
               JALR: 跳转并链接寄存器 (Jump and Link Register) x[rd] = pc+4; pc = x[rs1] + sext(offset)
            */
            `INST_JAL, `INST_JALR: begin
                hold_flag = `HoldDisable;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
                reg_wdata = op1_add_op2_res;
            end
            /* LUI: 高位立即数加载 (Load Upper Immediate) x[rd] = sext(immediate[31:12] << 12)
               AUIPC: PC 加立即数 (Add Upper Immediate to PC) x[rd] = pc + sext(immediate[31:12] << 12)
            */
            `INST_LUI, `INST_AUIPC: begin
                hold_flag = `HoldDisable;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                jump_addr = `ZeroWord;
                jump_flag = `JumpDisable;
                reg_wdata = op1_add_op2_res;
            end
            `INST_NOP_OP: begin  // 无操作 No opareation
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
            end
            `INST_FENCE: begin  // 内存屏障 (Memory Fence)
                hold_flag = `HoldDisable;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
            end
            `INST_CSR: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                case (funct3)
                    // 读后写控制状态寄存器 (Control and Status Register Read and Write).
                    `INST_CSRRW: begin  // t = CSRs[csr]; CSRs[csr] = x[rs1]; x[rd] = t
                        csr_wdata_o = reg1_rdata_i;
                        reg_wdata   = csr_rdata_i;
                    end
                    // 读后置位控制状态寄存器 (Control and Status Register Read and  Set).
                    `INST_CSRRS: begin  // t = CSRs[csr]; CSRs[csr] = t | x[rs1]; x[rd] = t
                        csr_wdata_o = reg1_rdata_i | csr_rdata_i;
                        reg_wdata   = csr_rdata_i;
                    end
                    // 读后清除控制状态寄存器 (Control and Status Register Read and Clear)
                    `INST_CSRRC: begin  // t = CSRs[csr]; CSRs[csr] = t &~x[rs1]; x[rd] = t
                        csr_wdata_o = csr_rdata_i & (~reg1_rdata_i);
                        reg_wdata   = csr_rdata_i;
                    end
                    // 立即数读后写控制状态寄存器 (Control and Status Register Read and Write Immediate)
                    `INST_CSRRWI: begin  // x[rd] = CSRs[csr]; CSRs[csr] = zimm
                        csr_wdata_o = {27'h0, uimm};
                        reg_wdata   = csr_rdata_i;
                    end
                    `INST_CSRRSI: begin
                        csr_wdata_o = {27'h0, uimm} | csr_rdata_i;
                        reg_wdata   = csr_rdata_i;
                    end
                    `INST_CSRRCI: begin
                        csr_wdata_o = (~{27'h0, uimm}) & csr_rdata_i;
                        reg_wdata   = csr_rdata_i;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            default: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
            end
        endcase
    end

endmodule
