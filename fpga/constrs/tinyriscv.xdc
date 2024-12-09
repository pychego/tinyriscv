#  已经根据xz7010的引脚分配修改 主要是uart_debug_pin, 这个接到一个空引脚, 
#  在使用jtag下载时,将该空引脚接地, 串口下载时,将该空引脚接到3.3V,不能使用拨码开关

# 时钟约束50MHz  	U18
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {clk}]; 
create_clock -add -name sys_clk_pin -period 20.00 -waveform {0 10} [get_ports {clk}];
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets jtag_TCK_IBUF] 
# 时钟引脚 ok   	U18
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN U18 [get_ports clk]

# 复位引脚  ok  	F20
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property PACKAGE_PIN F20 [get_ports rst]

# 程序执行完毕指示引脚 ok    LED0   G17
set_property IOSTANDARD LVCMOS33 [get_ports over]
set_property PACKAGE_PIN G17 [get_ports over]

# 程序执行成功指示引脚 ok   LED1  G19
set_property IOSTANDARD LVCMOS33 [get_ports succ]
set_property PACKAGE_PIN G19 [get_ports succ]
 
# CPU停住指示引脚 ok   LED2  G20
set_property IOSTANDARD LVCMOS33 [get_ports halted_ind]
set_property PACKAGE_PIN G20 [get_ports halted_ind]

# 串口下载使能引脚  ok    KEY0   H20  使用接地 N16引脚
set_property IOSTANDARD LVCMOS33 [get_ports uart_debug_pin]
set_property PACKAGE_PIN N16 [get_ports uart_debug_pin]

# 串口发送引脚  CMOS_PCLK  M17
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]
set_property PACKAGE_PIN M17 [get_ports uart_tx_pin]

# 串口接收引脚  CMOS_HREF  U13
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]
set_property PACKAGE_PIN U13 [get_ports uart_rx_pin]

# GPIO0引脚  ok  ------ LED6      H17
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[0]}]
set_property PACKAGE_PIN H17 [get_ports {gpio[0]}]

# GPIO1引脚  ok    KEY1   H16
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[1]}]
set_property PACKAGE_PIN H16 [get_ports {gpio[1]}]

# JTAG TCK引脚     CMOS_D0   J15
set_property IOSTANDARD LVCMOS33 [get_ports jtag_TCK]
set_property PACKAGE_PIN J15 [get_ports jtag_TCK]

#create_clock -name jtag_clk_pin -period 300 [get_ports {jtag_TCK}];

# JTAG TMS引脚  CMOS_D1   M14
set_property IOSTANDARD LVCMOS33 [get_ports jtag_TMS]
set_property PACKAGE_PIN M14 [get_ports jtag_TMS]

# JTAG TDI引脚 CMOS_D2  	N15
set_property IOSTANDARD LVCMOS33 [get_ports jtag_TDI]
set_property PACKAGE_PIN N15 [get_ports jtag_TDI]

# JTAG TDO引脚 	CMOS_D3   L14
set_property IOSTANDARD LVCMOS33 [get_ports jtag_TDO]
set_property PACKAGE_PIN L14 [get_ports jtag_TDO]

# SPI MISO引脚   	CMOS_D4   M15
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso]
set_property PACKAGE_PIN M15 [get_ports spi_miso]

# SPI MOSI引脚    CMOS_D5    K17
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi]
set_property PACKAGE_PIN K17 [get_ports spi_mosi]

# SPI SS引脚    CMOS_D6    L17
set_property IOSTANDARD LVCMOS33 [get_ports spi_ss]
set_property PACKAGE_PIN L17 [get_ports spi_ss]

# SPI CLK引脚   CMOS_D7    L16
set_property IOSTANDARD LVCMOS33 [get_ports spi_clk]
set_property PACKAGE_PIN L16 [get_ports spi_clk]

#set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]  
#set_property CONFIG_MODE SPIx4 [current_design] 
#set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
