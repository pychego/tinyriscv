import sys
import filecmp
import subprocess
import sys
import os

"""
    1.将bin文件转成mem文件 将c语言编译生成的bin文件转成mem文件(inst.data)
    2.编译rtl文件, 本质上就是用iverilog在命令行编译tinyriscv_soc_tb.v文件, 主要为了获取编译后文件 vpp
    3.运行iverilog仿真
"""


# 主函数
def main():
    # print(sys.argv[0] + ' ' + sys.argv[1] + ' ' + sys.argv[2])

    a = "..\tests\isa\generated\rv32ui-p-add.bin"
    b = "inst.data"

    # 1.将bin文件转成mem文件 将c语言编译生成的bin文件转成mem文件(inst.data)
    # inst.data就是bin文件转化成的mem文件 这个名字可以自定义,随便写
    # mem文件中存放的就是32bit的指令
    # 该指令生成inst.data文件
    cmd = r"python ../tools/BinToMem_CLI.py" + " " + sys.argv[1] + " " + sys.argv[2]
    f = os.popen(cmd)
    f.close()

    # 2.编译rtl文件, 本质上就是用iverilog在命令行编译tinyriscv_soc_tb.v文件
    cmd = r"python compile_rtl.py" + r" .."
    f = os.popen(cmd)
    f.close()

    # 3.运行  是在命令行运行吗 好像不是
    vvp_cmd = [r"vvp"]
    vvp_cmd.append(r"out.vvp")
    print(vvp_cmd)
    process = subprocess.Popen(vvp_cmd)
    try:
        process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        print("!!!Fail, vvp exec timeout!!!")


if __name__ == "__main__":
    sys.exit(main())
