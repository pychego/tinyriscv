#ifndef _TIMER_H_
#define _TIMER_H_

#define TIMER0_BASE   (0x20000000)      // 在rib中规定的timer0的基地址
#define TIMER0_CTRL   (TIMER0_BASE + (0x00))    // 都是在timer.v中定义的寄存器地址
#define TIMER0_COUNT  (TIMER0_BASE + (0x04))
#define TIMER0_VALUE  (TIMER0_BASE + (0x08))


/*  定义带参数的宏,(*((volatile uint32_t *)addr))执行如下操作
    1. (volatile uint32_t *)addr 将 addr 转换为一个指向 volatile uint32_t 类型的指针
        volatile 关键字告诉编译器这个内存位置可能会被硬件或其他线程修改，因此不要对其进行优化
    2. (*((volatile uint32_t *)addr)) 将指针解引用,得到一个 volatile uint32_t 类型的值
    具体看实际应用  TIMER0_REG(TIMER0_VALUE) = 500; 
    即  (*((volatile uint32_t *)TIMER0_VALUE)) = 500;
*/
#define TIMER0_REG(addr) (*((volatile uint32_t *)addr))

#endif
