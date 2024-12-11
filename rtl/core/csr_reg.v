`include "defines.v"

// CSR寄存器模块
/*  处理器中的csr寄存器都在此模块内, 用于处理器内部的控制和状态保存
    与ex和clint交互,主要实现来自ex和clint的对csr寄存器的读写操作, 写操作优先级ex>clint
    这里面读操作不是ex模块, 而是id模块进行的读操作
*/
module csr_reg (

    input wire clk,
    input wire rst,

    // form ex 或者 id
    input wire               we_i,     // ex模块写寄存器标志
    input wire [`MemAddrBus] raddr_i,  // id模块读寄存器地址
    input wire [`MemAddrBus] waddr_i,  // ex模块写寄存器地址
    input wire [    `RegBus] data_i,   // ex模块写寄存器数据

    // from clint, 根据状态机的状态,clint模块会读写csr_reg模块的寄存器
    input wire               clint_we_i,     // clint模块写寄存器标志
    input wire [`MemAddrBus] clint_raddr_i,  // clint模块读寄存器地址
    input wire [`MemAddrBus] clint_waddr_i,  // clint模块写寄存器地址
    input wire [    `RegBus] clint_data_i,   // clint模块写寄存器数据

    output wire global_int_en_o,  // 全局中断使能标志

    // to clint
    output reg  [`RegBus] clint_data_o,      // clint模块读寄存器数据
    output wire [`RegBus] clint_csr_mtvec,   // mtvec
    output wire [`RegBus] clint_csr_mepc,    // mepc
    output wire [`RegBus] clint_csr_mstatus, // mstatus

    // to id
    output reg [`RegBus] data_o  // id模块读寄存器数据

);


    /* mtvec Machine Trap Vector 它保存发生异常时处理器需要跳转到的地址
       mcause Machine Cause 它指示发生异常的种类
       mepc Machine Exception Program Counter 它指向发生异常的指令
       mie Machine Interrupt Enable 它指出处理器目前能处理和必须忽略的中断
       mstatus Machine Status 它保存全局中断使能，以及许多其他的状态
       mscratch Machine Scratch 它暂时存放一个字大小的数据
    */
    reg [`DoubleRegBus] cycle;
    reg [      `RegBus] mtvec;
    reg [      `RegBus] mcause;
    reg [      `RegBus] mepc;
    reg [      `RegBus] mie;
    reg [      `RegBus] mstatus;
    reg [      `RegBus] mscratch;

    // 处理器在M模式下运行时,只有在全局中断使能位mstatus[3]为1时才能产生中断
    assign global_int_en_o = (mstatus[3] == 1'b1) ? `True : `False;

    assign clint_csr_mtvec = mtvec; // Machine Trap Vector
    assign clint_csr_mepc = mepc;   // Machine Exception Program Counter
    assign clint_csr_mstatus = mstatus; // Machine Status

    // cycle counter 复位撤销后就一直计数
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            cycle <= {`ZeroWord, `ZeroWord};
        end else begin
            cycle <= cycle + 1'b1;
        end
    end

    /* write reg 写寄存器操作
       接收ex模块和clint模块的对csr寄存器的写操作,ex模块优先级更高
    */
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            mtvec <= `ZeroWord;
            mcause <= `ZeroWord;
            mepc <= `ZeroWord;
            mie <= `ZeroWord;
            mstatus <= `ZeroWord;
            mscratch <= `ZeroWord;
        end else begin
            // 优先响应ex模块的写操作
            if (we_i == `WriteEnable) begin
                case (waddr_i[11:0])    // CSR reg addr
                    `CSR_MTVEC: begin
                        mtvec <= data_i;
                    end
                    `CSR_MCAUSE: begin
                        mcause <= data_i;
                    end
                    `CSR_MEPC: begin
                        mepc <= data_i;
                    end
                    `CSR_MIE: begin
                        mie <= data_i;
                    end
                    `CSR_MSTATUS: begin
                        mstatus <= data_i;
                    end
                    `CSR_MSCRATCH: begin
                        mscratch <= data_i;
                    end
                    default: begin

                    end
                endcase
                // clint模块写操作
            end else if (clint_we_i == `WriteEnable) begin
                case (clint_waddr_i[11:0])
                    `CSR_MTVEC: begin
                        mtvec <= clint_data_i;
                    end
                    `CSR_MCAUSE: begin
                        mcause <= clint_data_i;
                    end
                    `CSR_MEPC: begin
                        mepc <= clint_data_i;
                    end
                    `CSR_MIE: begin
                        mie <= clint_data_i;
                    end
                    `CSR_MSTATUS: begin
                        mstatus <= clint_data_i;
                    end
                    `CSR_MSCRATCH: begin
                        mscratch <= clint_data_i;
                    end
                    default: begin

                    end
                endcase
            end
        end
    end

    // read reg
    // ex模块读CSR寄存器
    always @(*) begin  // 如果写使能,且写地址等于读地址,则输出写数据
        if ((waddr_i[11:0] == raddr_i[11:0]) && (we_i == `WriteEnable)) begin
            data_o = data_i;
        end else begin
            case (raddr_i[11:0])
                `CSR_CYCLE: begin  
                    data_o = cycle[31:0];
                end
                `CSR_CYCLEH: begin  // 读周期计数器高位
                    data_o = cycle[63:32];
                end
                `CSR_MTVEC: begin
                    data_o = mtvec;
                end
                `CSR_MCAUSE: begin
                    data_o = mcause;
                end
                `CSR_MEPC: begin
                    data_o = mepc;
                end
                `CSR_MIE: begin
                    data_o = mie;
                end
                `CSR_MSTATUS: begin
                    data_o = mstatus;
                end
                `CSR_MSCRATCH: begin
                    data_o = mscratch;
                end
                default: begin
                    data_o = `ZeroWord;
                end
            endcase
        end
    end

    // read reg
    // clint模块读CSR寄存器
    always @(*) begin
        if ((clint_waddr_i[11:0] == clint_raddr_i[11:0]) && (clint_we_i == `WriteEnable)) begin
            clint_data_o = clint_data_i;
        end else begin
            case (clint_raddr_i[11:0])
                `CSR_CYCLE: begin
                    clint_data_o = cycle[31:0];
                end
                `CSR_CYCLEH: begin
                    clint_data_o = cycle[63:32];
                end
                `CSR_MTVEC: begin
                    clint_data_o = mtvec;
                end
                `CSR_MCAUSE: begin
                    clint_data_o = mcause;
                end
                `CSR_MEPC: begin
                    clint_data_o = mepc;
                end
                `CSR_MIE: begin
                    clint_data_o = mie;
                end
                `CSR_MSTATUS: begin
                    clint_data_o = mstatus;
                end
                `CSR_MSCRATCH: begin
                    clint_data_o = mscratch;
                end
                default: begin
                    clint_data_o = `ZeroWord;
                end
            endcase
        end
    end

endmodule
