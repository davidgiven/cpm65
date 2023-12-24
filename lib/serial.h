#ifndef SERIAL_H
#define SERIAL_H

extern uint8_t serial_init(void);
extern void serial_open(uint16_t flags);
extern void serial_close(void);
extern uint8_t serial_inp(void);
extern void serial_out(uint8_t c);
extern uint8_t serial_outp(uint8_t c);
extern uint8_t serial_in(void); 

#endif

