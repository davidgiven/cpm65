#ifndef SCREEN_H
#define SCREEN_H

extern uint8_t screen_init(void);

extern void screen_clear(void);
extern uint16_t _screen_getsize(void);
extern void _screen_setcursor(uint16_t c);
extern uint16_t _screen_getcursor(void);
extern void screen_putchar(char c);
extern void screen_putstring(const char* s);
extern uint16_t screen_getchar(uint16_t timeout_cs);
extern uint8_t screen_waitchar(void);
extern void screen_scrollup(void);
extern void screen_scrolldown(void);
extern void screen_clear_to_eol(void);
extern void screen_setstyle(uint8_t style);

#define screen_setcursor(x, y) \
	_screen_setcursor((x) | ((y)<<8))

#define screen_getsize(wp, hp) \
	do { \
		uint16_t c = _screen_getsize(); \
		*(wp) = c & 0xff; \
		*(hp) = c >> 8; \
	} while(0)

#define screen_getcursor(wp, hp) \
	do { \
		uint16_t c = _screen_getcursor(); \
		*(wp) = c & 0xff; \
		*(hp) = c >> 8; \
	} while(0)

#endif

