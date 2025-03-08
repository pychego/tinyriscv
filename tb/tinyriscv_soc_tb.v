`timescale 1 ns / 1 ps

`include "defines.v"

// select one option only  一种是直接将inst.data放入rom中执行, 一种使用jtag进行测试; 
/*  TEST_PROG 和 TEST_JTAG 不知道有啥区别, 两者都使用了inst.data文件放入rom中执行
*/
// `define TEST_PROG 1
`define TEST_JTAG 1

/*  测试老的指令集使用这个tb
*/

// testbench module
module tinyriscv_soc_tb;

    reg clk;
    reg rst;


    always #10 clk = ~clk;  // 50MHz

    /* tinyriscv内部的32个通用寄存器
       x3: gp    测试编号, 表明目前是第几次测试
       x26: s10  测试结束标志: x26=1
       x27: s11  测试通过则x27=1
    */
    wire    [`RegBus] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    wire    [`RegBus] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    wire    [`RegBus] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];


    integer                                                                  r;

`ifdef TEST_JTAG
    reg TCK;
    reg TMS;
    reg TDI;
    wire TDO;

    integer i;
    reg [39:0] shift_reg;
    reg in;
    wire [39:0] req_data = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.dtm_req_data;
    wire [4:0] ir_reg = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.ir_reg;
    wire dtm_req_valid = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.dtm_req_valid;
    wire [31:0] dmstatus = tinyriscv_soc_top_0.u_jtag_top.u_jtag_dm.dmstatus;
`endif

    initial begin
        clk = 0;
        rst = `RstEnable;
`ifdef TEST_JTAG
        TCK = 1;
        TMS = 1;
        TDI = 1;
`endif
        $display("test running...");
        #40 rst = `RstDisable;
        #200

`ifdef TEST_PROG
        wait (x26 == 32'b1)  // wait sim end, when x26 == 1
            #100
                if (x27 == 32'b1) begin
                    $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
                    $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
                    $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
                    $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
                    $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
                    $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                end else begin
                    $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
                    $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
                    $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
                    $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
                    $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
                    $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("fail testnum = %2d", x3);
                    for (r = 0; r < 32; r = r + 1)
                        $display("x%2d = 0x%x", r, tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[r]);
                end
`endif

`ifdef TEST_JTAG
        // reset
        for (i = 0; i < 8; i++) begin
            TMS = 1;
            TCK = 0;
            #100 TCK = 1;
            #100 TCK = 0;
        end

        // IR
        shift_reg = 40'b10001;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SELECT-IR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // CAPTURE-IR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-IR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-IR & EXIT1-IR
        for (i = 5; i > 0; i--) begin
            if (shift_reg[0] == 1'b1) TDI = 1'b1;
            else TDI = 1'b0;

            if (i == 1) TMS = 1;

            TCK = 0;
            #100 in = TDO;
            TCK = 1;
            #100 TCK = 0;

            shift_reg = {{(35) {1'b0}}, in, shift_reg[4:1]};
        end

        // PAUSE-IR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // EXIT2-IR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // UPDATE-IR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // dmi write
        shift_reg = {6'h10, {(32) {1'b0}}, 2'b10};

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0] == 1'b1) TDI = 1'b1;
            else TDI = 1'b0;

            if (i == 1) TMS = 1;

            TCK = 0;
            #100 in = TDO;
            TCK = 1;
            #100 TCK = 0;

            shift_reg = {in, shift_reg[39:1]};
        end

        // PAUSE-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // EXIT2-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // UPDATE-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        $display("ir_reg = 0x%x", ir_reg);
        $display("dtm_req_valid = %d", dtm_req_valid);
        $display("req_data = 0x%x", req_data);

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        $display("dmstatus = 0x%x", dmstatus);

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // dmi read
        shift_reg = {6'h11, {(32) {1'b0}}, 2'b01};

        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0] == 1'b1) TDI = 1'b1;
            else TDI = 1'b0;

            if (i == 1) TMS = 1;

            TCK = 0;
            #100 in = TDO;
            TCK = 1;
            #100 TCK = 0;

            shift_reg = {in, shift_reg[39:1]};
        end

        // PAUSE-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // EXIT2-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // UPDATE-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // dmi read
        shift_reg = {6'h11, {(32) {1'b0}}, 2'b00};

        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100 TCK = 1;
        #100 TCK = 0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0] == 1'b1) TDI = 1'b1;
            else TDI = 1'b0;

            if (i == 1) TMS = 1;

            TCK = 0;
            #100 in = TDO;
            TCK = 1;
            #100 TCK = 0;

            shift_reg = {in, shift_reg[39:1]};
        end

        #100 $display("shift_reg = 0x%x", shift_reg[33:2]);

        if (dmstatus == shift_reg[33:2]) begin
            $display("######################");
            $display("### jtag test pass ###");
            $display("######################");
        end else begin
            $display("######################");
            $display("!!! jtag test fail !!!");
            $display("######################");
        end
`endif

        $finish;
    end

    // sim timeout
    initial begin
      #500000 $display("Time Out.");
        $finish;
    end

    // read mem data
    initial begin
        $readmemh("inst.data", tinyriscv_soc_top_0.u_rom._rom);
    end

    // generate wave file, used by gtkwave
    initial begin
        $dumpfile("tinyriscv_soc_tb.vcd");
        $dumpvars(0, tinyriscv_soc_tb);  // dump all signals
    end

    tinyriscv_soc_top tinyriscv_soc_top_0 (
        .clk           (clk),
        .rst           (rst),
        .uart_debug_pin(1'b0)   // 不使能uart_debug
`ifdef TEST_JTAG,
        .jtag_TCK      (TCK),
        .jtag_TMS      (TMS),
        .jtag_TDI      (TDI),
        .jtag_TDO      (TDO)
`endif
    );

endmodule
