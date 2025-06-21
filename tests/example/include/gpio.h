#ifndef _GPIO_H_
#define _GPIO_H_

#define GPIO_BASE      (0x40000000)
#define GPIO_CTRL      (GPIO_BASE + (0x00))
#define GPIO_DATA      (GPIO_BASE + (0x04))

// 直接使用地址解引这个地址的寄存器赋值
#define GPIO_REG(addr) (*((volatile uint32_t *)addr))

#endif
