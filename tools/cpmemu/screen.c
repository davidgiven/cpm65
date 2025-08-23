#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdarg.h>
#include <termios.h>
#include <unistd.h>
#include <ctype.h>
#include "globals.h"

static struct termios original_termios;

static void switch_to_raw_mode(void)
{
    if (tcgetattr(0, &original_termios) < 0)
        fatal("can't get tty settings");

    struct termios raw = original_termios;

    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);

    tcsetattr(0, TCSAFLUSH, &raw);
}

static void switch_to_cooked_mode(void)
{
    tcsetattr(0, TCSAFLUSH, &original_termios);
}

void screen_entry(uint8_t op)
{
    switch (op)
    {
        case 0: /* SCREEN_VERSION */
            set_result(0, true);
            return;

        case 1: /* SCREEN_GETSIZE */
            cpu->registers->a = 79;
            cpu->registers->x = 24;
            cpu->registers->p &= ~0x01;
            return;

        case 2: /* SCREEN_CLEAR */
            fprintf(stderr, "screen_clear()\n");
            return;

        case 3: /* SCREEN_SETCURSOR */
            fprintf(stderr,
                "screen_setcursor(%d, %d)\n",
                cpu->registers->a,
                cpu->registers->x);
            return;

        case 4: /* SCREEN_GETCURSOR */
            fprintf(stderr, "screen_getcursor()\n");
            cpu->registers->a = cpu->registers->x = 0;
            return;

        case 5: /* SCREEN_PUTCHAR */
            fprintf(stderr, "screen_putchar(%1$d '%1$c')\n", cpu->registers->a);
            if (!isprint(cpu->registers->a))
                singlestepping = true;
            return;

        case 6: /* SCREEN_PUTSTRING */
        {
            fprintf(stderr, "screen_putstring(\"");
            uint16_t xa = get_xa();
            for (;;)
            {
                uint8_t c = ram[xa++];
                if (!c)
                    break;
                putchar(c);
            }
            fprintf(stderr, "\"");
            return;
        }

        case 7: /* SCREEN_GETCHAR */
            fprintf(stderr, "screen_getchar(%d)\n", get_xa());
            switch_to_raw_mode();
            read(0, &cpu->registers->a, 1);
            switch_to_cooked_mode();
            cpu->registers->p &= ~0x01;
            return;

        case 8: /* SCREEN_SHOWCURSOR */
            fprintf(stderr, "screen_showcursor()\n");
            return;

        case 9: /* SCREEN_SCROLLUP */
            fprintf(stderr, "screen_scrollup()\n");
            return;

        case 10: /* SCREEN_SCROLLDOWN */
            fprintf(stderr, "screen_scrolldown()\n");
            return;

        case 11: /* SCREEN_CLEARTOEOL */
            fprintf(stderr, "screen_cleartoeol()\n");
            return;

        case 12: /* SCREEN_SETSTYLE */
            fprintf(stderr, "screen_setstyle(0x%02x)\n", cpu->registers->a);
            return;
    }

    showregs();
    fatal("unimplemented SCREEN entry %d", op);
}
