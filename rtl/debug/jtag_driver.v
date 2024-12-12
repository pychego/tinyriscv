/*                                                                      
    与作者的gitee上面的deep_in_riscv_debug项目的readme文件对照理解
    该代码是riscv调试系统框架中的DTM(Debug Transport Module)模块, 实现了TAP状态机                                        
 */

`define DM_RESP_VALID 1'b1
`define DM_RESP_INVALID 1'b0
`define DTM_REQ_VALID 1'b1
`define DTM_REQ_INVALID 1'b0


module jtag_driver #(
    parameter DMI_ADDR_BITS = 6,
    parameter DMI_DATA_BITS = 32,
    parameter DMI_OP_BITS   = 2
) (

    rst_n,

    jtag_TCK,
    jtag_TDI,
    jtag_TMS,
    jtag_TDO,

    // rx
    dm_resp_i,
    dm_resp_data_i,
    dtm_ack_o,

    // tx
    dm_ack_i,
    dtm_req_valid_o,
    dtm_req_data_o

);

    parameter IDCODE_VERSION = 4'h1;
    parameter IDCODE_PART_NUMBER = 16'he200;
    parameter IDCODE_MANUFLD = 11'h537;

    parameter DTM_VERSION = 4'h1;
    parameter IR_BITS = 5;

    parameter DM_RESP_BITS = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;  // 40
    parameter DTM_REQ_BITS = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;  // 40
    parameter SHIFT_REG_BITS = DTM_REQ_BITS;  // 40

    // input and output
    input wire rst_n;
    input wire jtag_TCK;
    input wire jtag_TDI;
    input wire jtag_TMS;
    output reg jtag_TDO;

    // 与DM模块交互
    input wire dm_resp_i;
    input wire [DM_RESP_BITS - 1:0] dm_resp_data_i;
    output wire dtm_ack_o;
    input wire dm_ack_i;
    output wire dtm_req_valid_o;
    output wire [DTM_REQ_BITS - 1:0] dtm_req_data_o;

    // JTAG StateMachine 每个芯片的内部都有JTAG TAP控制器,有16个状态
    parameter TEST_LOGIC_RESET = 4'h0;  // 上电后的初始状态
    parameter RUN_TEST_IDLE = 4'h1;
    parameter SELECT_DR = 4'h2;
    parameter CAPTURE_DR = 4'h3;
    parameter SHIFT_DR = 4'h4;
    parameter EXIT1_DR = 4'h5;
    parameter PAUSE_DR = 4'h6;
    parameter EXIT2_DR = 4'h7;
    parameter UPDATE_DR = 4'h8;
    parameter SELECT_IR = 4'h9;
    parameter CAPTURE_IR = 4'hA;
    parameter SHIFT_IR = 4'hB;
    parameter EXIT1_IR = 4'hC;
    parameter PAUSE_IR = 4'hD;
    parameter EXIT2_IR = 4'hE;
    parameter UPDATE_IR = 4'hF;

    /* DTM regs DMT中必须实现的寄存器
       后面的值是当IR(instruction register)寄存器的值是这个的话,对应选择的DR(data register)寄存器
     */
    parameter REG_BYPASS = 5'b11111;
    parameter REG_IDCODE = 5'b00001;
    parameter REG_DMI = 5'b10001;
    parameter REG_DTMCS = 5'b10000;

    reg  [       IR_BITS - 1:0]                                 ir_reg;
    reg  [SHIFT_REG_BITS - 1:0]                                 shift_reg;
    reg  [                 3:0]                                 jtag_state;
    wire                                                        is_busy;
    reg                                                         sticky_busy;
    reg                                                         dtm_req_valid;
    reg  [  DTM_REQ_BITS - 1:0]                                 dtm_req_data;
    reg  [  DM_RESP_BITS - 1:0]                                 dm_resp_data;
    reg                                                         dm_is_busy;

    wire [                 5:0] addr_bits = DMI_ADDR_BITS[5:0];
    wire [SHIFT_REG_BITS - 1:0]                                 busy_response;
    wire [SHIFT_REG_BITS - 1:0]                                 none_busy_response;
    wire [                31:0]                                 idcode;
    wire [                31:0]                                 dtmcs;
    wire [                 1:0]                                 dmi_stat;
    wire                                                        dtm_reset;
    wire                                                        tx_idle;
    wire                                                        rx_valid;
    wire [  DM_RESP_BITS - 1:0]                                 rx_data;
    wire                                                        tx_valid;
    wire [  DTM_REQ_BITS - 1:0]                                 tx_data;

    assign dtm_reset = shift_reg[16];
    assign idcode = {IDCODE_VERSION, IDCODE_PART_NUMBER, IDCODE_MANUFLD, 1'h1};
    assign dtmcs = {
        14'b0,
        1'b0,  // dmihardreset
        1'b0,  // dmireset
        1'b0,
        3'h5,  // idle
        dmi_stat,   // dmistat,只读,上一次操作的状态,0表示无出错,1或者2表示出错,3表示操作还未完成
        addr_bits,  // abits 只读，dmi寄存器中address域的大小(位数)
        DTM_VERSION // 只读，实现所对应的spec版本，0表示0.11版本，1表示0.13版本
    };  // version


    // 往DM模块发送busy_response和none_busy_response
    assign busy_response = {
        {(DMI_ADDR_BITS + DMI_DATA_BITS) {1'b0}}, {(DMI_OP_BITS) {1'b1}}
    };  // op = 2'b11
    assign none_busy_response = dm_resp_data;
    assign is_busy = sticky_busy | dm_is_busy;
    assign dmi_stat = is_busy ? 2'b01 : 2'b00;

    // state switch TAP控制器的状态机
    always @(posedge jtag_TCK or negedge rst_n) begin
        if (!rst_n) begin
            jtag_state <= TEST_LOGIC_RESET;
        end else begin
            case (jtag_state)
                TEST_LOGIC_RESET: jtag_state <= jtag_TMS ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
                RUN_TEST_IDLE:    jtag_state <= jtag_TMS ? SELECT_DR : RUN_TEST_IDLE;
                SELECT_DR:        jtag_state <= jtag_TMS ? SELECT_IR : CAPTURE_DR;
                CAPTURE_DR:       jtag_state <= jtag_TMS ? EXIT1_DR : SHIFT_DR;
                SHIFT_DR:         jtag_state <= jtag_TMS ? EXIT1_DR : SHIFT_DR;
                EXIT1_DR:         jtag_state <= jtag_TMS ? UPDATE_DR : PAUSE_DR;
                PAUSE_DR:         jtag_state <= jtag_TMS ? EXIT2_DR : PAUSE_DR;
                EXIT2_DR:         jtag_state <= jtag_TMS ? UPDATE_DR : SHIFT_DR;
                UPDATE_DR:        jtag_state <= jtag_TMS ? SELECT_DR : RUN_TEST_IDLE;
                SELECT_IR:        jtag_state <= jtag_TMS ? TEST_LOGIC_RESET : CAPTURE_IR;
                CAPTURE_IR:       jtag_state <= jtag_TMS ? EXIT1_IR : SHIFT_IR;
                SHIFT_IR:         jtag_state <= jtag_TMS ? EXIT1_IR : SHIFT_IR;
                EXIT1_IR:         jtag_state <= jtag_TMS ? UPDATE_IR : PAUSE_IR;
                PAUSE_IR:         jtag_state <= jtag_TMS ? EXIT2_IR : PAUSE_IR;
                EXIT2_IR:         jtag_state <= jtag_TMS ? UPDATE_IR : SHIFT_IR;
                UPDATE_IR:        jtag_state <= jtag_TMS ? SELECT_DR : RUN_TEST_IDLE;
            endcase
        end
    end

    // IR or DR shift 看不懂
    always @(posedge jtag_TCK) begin
        case (jtag_state)
            // IR
            CAPTURE_IR:
            shift_reg <= {{(SHIFT_REG_BITS - 1) {1'b0}}, 1'b1};  //JTAG spec says it must be b01
            SHIFT_IR:
            shift_reg <= {
                {(SHIFT_REG_BITS - IR_BITS) {1'b0}}, jtag_TDI, shift_reg[IR_BITS-1:1]
            };  // right shift 1 bit  右移1bit 将jtag_TDI放入高位
            // DR
            CAPTURE_DR:     // 捕获数据寄存器(DR)状态
            case (ir_reg)
                REG_BYPASS: shift_reg <= {(SHIFT_REG_BITS) {1'b0}};
                REG_IDCODE: shift_reg <= {{(SHIFT_REG_BITS - DMI_DATA_BITS) {1'b0}}, idcode};
                REG_DTMCS:  shift_reg <= {{(SHIFT_REG_BITS - DMI_DATA_BITS) {1'b0}}, dtmcs};
                REG_DMI:    shift_reg <= is_busy ? busy_response : none_busy_response;
                default:    shift_reg <= {(SHIFT_REG_BITS) {1'b0}};
            endcase
            SHIFT_DR:       // 移位数据寄存器(DR)状态
            case (ir_reg)
                REG_BYPASS: shift_reg <= {{(SHIFT_REG_BITS - 1) {1'b0}}, jtag_TDI};  // in = out
                REG_IDCODE:
                shift_reg <= {
                    {(SHIFT_REG_BITS - DMI_DATA_BITS) {1'b0}}, jtag_TDI, shift_reg[31:1]
                };  // right shift 1 bit
                REG_DTMCS:
                shift_reg <= {
                    {(SHIFT_REG_BITS - DMI_DATA_BITS) {1'b0}}, jtag_TDI, shift_reg[31:1]
                };  // right shift 1 bit
                REG_DMI:
                shift_reg <= {jtag_TDI, shift_reg[SHIFT_REG_BITS-1:1]};  // right shift 1 bit
                default: shift_reg <= {{(SHIFT_REG_BITS - 1) {1'b0}}, jtag_TDI};
            endcase
        endcase
    end

    // start access DM module
    always @(posedge jtag_TCK or negedge rst_n) begin
        if (!rst_n) begin
            dtm_req_valid <= `DTM_REQ_INVALID;
            dtm_req_data  <= {DTM_REQ_BITS{1'b0}};
        end else begin
            if (jtag_state == UPDATE_DR) begin
                if (ir_reg == REG_DMI) begin
                    // if DM can be access
                    if (!is_busy & tx_idle) begin
                        dtm_req_valid <= `DTM_REQ_VALID;
                        dtm_req_data  <= shift_reg;
                    end
                end
            end else begin
                dtm_req_valid <= `DTM_REQ_INVALID;
            end
        end
    end

    assign tx_valid = dtm_req_valid;
    assign tx_data  = dtm_req_data;

    // DTM reset  看不懂
    always @(posedge jtag_TCK or negedge rst_n) begin
        if (!rst_n) begin
            sticky_busy <= 1'b0;
        end else begin
            if (jtag_state == UPDATE_DR) begin
                if (ir_reg == REG_DTMCS & dtm_reset) begin
                    sticky_busy <= 1'b0;
                end
            end else if (jtag_state == CAPTURE_DR) begin
                if (ir_reg == REG_DMI) begin
                    sticky_busy <= is_busy;
                end
            end
        end
    end

    // receive DM response data
    always @(posedge jtag_TCK or negedge rst_n) begin
        if (!rst_n) begin
            dm_resp_data <= {DM_RESP_BITS{1'b0}};
        end else begin
            if (rx_valid) begin
                dm_resp_data <= rx_data;
            end
        end
    end

    // tx busy
    always @(posedge jtag_TCK or negedge rst_n) begin
        if (!rst_n) begin
            dm_is_busy <= 1'b0;
        end else begin
            if (dtm_req_valid) begin
                dm_is_busy <= 1'b1;
            end else if (rx_valid) begin
                dm_is_busy <= 1'b0;
            end
        end
    end

    // TAP reset
    always @(negedge jtag_TCK) begin
        if (jtag_state == TEST_LOGIC_RESET) begin
            ir_reg <= REG_IDCODE;
        end else if (jtag_state == UPDATE_IR) begin
            ir_reg <= shift_reg[IR_BITS-1:0];
        end
    end

    // TDO output  在SHIFT_IR和SHIFT_DR状态 TDI通过shift_reg与TDO形成闭环
    always @(negedge jtag_TCK) begin
        if (jtag_state == SHIFT_IR) begin
            jtag_TDO <= shift_reg[0];
        end else if (jtag_state == SHIFT_DR) begin
            jtag_TDO <= shift_reg[0];
        end else begin
            jtag_TDO <= 1'b0;
        end
    end

    full_handshake_tx #(
        .DW(DTM_REQ_BITS)
    ) tx (
        .clk       (jtag_TCK),
        .rst_n     (rst_n),
        .ack_i     (dm_ack_i),  // RX端应答信号,收到之后为第三次握手
        .req_i     (tx_valid),  // 来自其他tx模块发送的信号, 这里其实就是本模块生成的数据想要进行传输
        .req_data_i(tx_data),   // 同上
        .idle_o    (tx_idle),   // TX端是否空闲信号，空闲才能发数据
        .req_o     (dtm_req_valid_o),  // TX端请求信号, 第一次握手发出
        .req_data_o(dtm_req_data_o)    // TX端要发送的数据, 第一次握手发出
    );

    full_handshake_rx #(
        .DW(DM_RESP_BITS)
    ) rx (
        .clk        (jtag_TCK),
        .rst_n      (rst_n),
        .req_i      (dm_resp_i),    // rx接受tx的req信号
        .req_data_i (dm_resp_data_i),
        .ack_o      (dtm_ack_o),   // 接收到req信号后,发送ack信号
        .recv_data_o(rx_data),
        .recv_rdy_o (rx_valid)
    );

endmodule
