/* Conway's Game of Life for CP/M-65 - Copyright (c) 2023 Henrik Löfgren
 * This program is distributable under the terms of the 2-clause BSD license.
 * See COPYING.cpmish in the distribution root directory for more information. *
 * Screen driver is required.
 */

#include <cpm.h>
#include <stdio.h>
#include "lib/screen.h"
#include "lib/printi.h"

static uint8_t xpos = 0;
static uint8_t ypos = 0;
static uint8_t w,h;
static uint8_t screen = 0;

uint8_t buf_a[2560]; // Assuming 80x32 is maximum screen size
uint8_t buf_b[2560]; // Should be enough for everyone, right? ;)

void life(void) 
{
    uint8_t x,y;
    uint8_t sum;
    uint8_t c,a;
    uint16_t addr;
    
    // Advance one generation
    
    addr = w + 1;
    for(y=1; y<h; y++) 
    {
        for(x=0; x<w+1; x++) 
        {
            sum = 0;
            sum += buf_a[addr - w - 2];
            sum += buf_a[addr - w - 1];
            sum += buf_a[addr - w];
            sum += buf_a[addr - 1];
            sum += buf_a[addr + 1];
            sum += buf_a[addr + w];
            sum += buf_a[addr + w + 1];
            sum += buf_a[addr + w + 2];

            c = buf_a[addr];
            a = 0;
            if(c == 1 && ((sum == 2) || (sum == 3))) a = 1;
            if(c == 0 && sum == 3) a = 1;
            buf_b[addr] = a;
            addr++;
        }
    }
    

    // Render updated screen
    addr = 0;

    screen_setcursor(0,0);
    for(y=0; y<h; y++) 
    {
        for(x=0; x<(w+1); x++) 
        {
            buf_a[addr]=buf_b[addr];
            if(buf_b[addr] == 0)
                screen_putchar(' ');
            else
                screen_putchar('X');
            addr++;
        }
    } 
}

static void cr(void) 
{
    cpm_printstring("\n\r");
}

static void fatal(const char* msg) 
{
    cpm_printstring("Error: ");
    cpm_printstring(msg);
    cr();
    cpm_warmboot();
}

int main(void) 
{
    uint8_t inp;
    uint8_t run;
    uint16_t i;
    if(!screen_init())
        fatal("No SCREEN driver, exiting");
    
    screen_getsize(&w, &h);

    for(i=0; i<2400; i++)
        buf_a[i]=0;

    screen_clear();
    screen_setcursor(1,1);
    run = 1;
    while(run) 
    {
        screen_getcursor(&xpos, &ypos);
        screen_setcursor(0,h);
        cpm_printstring("LIFE Nav: W,A,S,D Tgl: T Go: G Quit: Q");
        screen_clear_to_eol();        

        screen_setcursor(xpos, ypos);

        inp=screen_waitchar();
        
        switch(inp) 
        {
            case 'a': // Cursor left
            case 'A':
                if(xpos > 0)
                    xpos--;
                break;
            case 'd': // Cursor right
            case 'D':
                if(xpos < w+1)
                    xpos++;
                break;
            case 'w': // Cursor up
            case 'W':
                if(ypos > 1)
                    ypos--;
                break;
            case 's': // Cursor down
            case 'S':
                if(ypos < h)
                    ypos++;
                break;
            case 't': // Toggle cell
            case 'T':
                i = ypos*(w+1)+xpos;
                if(buf_a[i]==0) 
                {
                    buf_a[i]=1; 
                    screen_putchar('X');
                } else 
                {
                    buf_a[i]=0;
                    screen_putchar(' ');
                }
                break;
            case 'g': // Go - 1 generation
            case 'G':
                life();
                break;
            case 'q': // Quit
            case 'Q':
                run=0;
                break;
            default:
                break;

        }
        screen_setcursor(xpos,ypos);
    }
    screen_clear();
    cpm_warmboot();
}
