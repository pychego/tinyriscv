#include <stdint.h>

#include "../include/timer.h"
#include "../include/gpio.h"
#include "../include/utils.h"


static volatile uint32_t count;


int main()
{
    count = 0;
/*
#ifdef SIMULATION        // 使用python执行tinyriscv_tb文件进行仿真执行时用这个
    // (*((volatile uint32_t *)TIMER0_VALUE)) = 500;
    TIMER0_REG(TIMER0_VALUE) = 500;     // 10us period
    TIMER0_REG(TIMER0_CTRL) = 0x07;     // enable interrupt and start timer

    while (1) {
        if (count == 2) {
            TIMER0_REG(TIMER0_CTRL) = 0x00;   // stop timer
            count = 0;
            // TODO: do something
            set_test_pass();
            break;
        }
    }
#else  // 真正上板子使用openocd下载时用这个
    TIMER0_REG(TIMER0_VALUE) = 500000;  // 10ms period
    TIMER0_REG(TIMER0_CTRL) = 0x07;     // enable interrupt and start timer

    // 上板有rst, 刚开始gpio_ctrl的值为0x0
    GPIO_REG(GPIO_CTRL) |= 0x1;  // set gpio0 output mode  按位或操作
    //  这里设置gpio_ctrl[1:0]=0x01, gpio_ctrl[3:2]=0x00, gpio.v里面写0为高阻态 
    //    但是看tinyriscv_soc_top里面, gpio这样也是输入, 不是高阻态
     

    while (1) {
        // 500ms
        if (count == 50) {
            count = 0;
            GPIO_REG(GPIO_DATA) ^= 0x1; // toggle led
        }
    }
#endif
*/
    TIMER0_REG(TIMER0_VALUE) = 500000;  // 10ms period
    TIMER0_REG(TIMER0_CTRL) = 0x07;     // enable interrupt and start timer

    // 上板有rst, 刚开始gpio_ctrl的值为0x0
    GPIO_REG(GPIO_CTRL) |= 0x1;  // set gpio0 output mode  按位或操作
    //  这里设置gpio_ctrl[1:0]=0x01, gpio_ctrl[3:2]=0x00, gpio.v里面写0为高阻态 
    //    但是看tinyriscv_soc_top里面, gpio这样也是输入, 不是高阻态
     

    while (1) {
        // 500ms
        if (count == 50) {
            count = 0;
            GPIO_REG(GPIO_DATA) ^= 0x1; // toggle led
        }
    }

    return 0;
}

// 这个中断处理程序是怎么和上面联系起来的???
// 这个应该是编译过程中,自动将这个函数作为中断处理函数,放到中断向量表中
void timer0_irq_handler()
{
    TIMER0_REG(TIMER0_CTRL) |= (1 << 2) | (1 << 0);  // clear int pending and start timer

    count++;
}
