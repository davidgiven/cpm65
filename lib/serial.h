#ifndef SERIAL_H
#define SERIAL_H

extern uint8_t serial_init(void);
extern void serial_open(uint16_t flags);
extern void serial_close(void);
extern uint16_t _serial_inp(void);
extern void serial_out(uint8_t c);
extern uint8_t serial_outp(uint8_t c);
extern uint8_t serial_in(void); 

#define serial_inp(dp, ap) \
    do { \
        uint16_t c = _serial_inp(); \
        *(dp) = c & 0xff; \
        *(ap) = c >> 8; \
    } while(0)
         

#endif

