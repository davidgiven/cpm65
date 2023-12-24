/* vt52term - Copyright (c) Henrik Löfgren
 * This program is redistributable under the terms of the 2-clause BSD license.
 * See LICENSE in the distribution root directory for more information
 *
 * A VT52 terminal emulator for CP/M-65. Works well enough to login and run
 * vim on a linux server (if the shell is configured correctly for VT52).
 * Requires SCREEN and SERIAL drivers.
 * 
 * VT52 parsing code heavily inspired by Kenneth Gobers VT52 terminal emulator for 
 * windows, see https://github.com/kgober/VT52/
 *
 * Commands:
 * Ctrl-q + q   -   Quit
 * Ctrl-q + e   -   Local echo on/off (default off)
 * Ctrl-q + v   -   VT52 emulation on/off (default on)
 *
 * TODO:
 * Implement arrow keys (needs updated screen driver)
 * Implement port settings (needs updated serial driver)
 * Implement some sort of output showing current settings
 * Implement Xon/Xoff flow control
 * Add xmodem send/receive to allow file transfer
*/
 
#include <cpm.h>
#include <stdio.h>
#include "lib/serial.h"
#include "lib/screen.h"

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
    uint8_t local_echo = 0;
    uint8_t vt52 = 1;
    uint8_t cur_x, cur_y;
    uint8_t w,h,i;
    uint8_t mEsc=0;
    uint8_t parse=0;
    if(!serial_init())
        fatal("No SERIAL driver, exiting");

    if(!screen_init())
        fatal("No SCREEN driver, exiting");

    // Open serial port
    serial_open(0);
    
    cpm_printstring("VT52 terminal emulator - Press ctrl-q + q to quit");
    cr();
    
    screen_getsize(&w, &h);
    
    while(1) { 
        inp = 0;
        // Check for data on serial port and parse it
        inp = serial_inp();
        parse = 1;
        if(vt52) {        
            if((inp >= 32) && (inp < 127)) {
                switch(mEsc) {
                    case 0: // Regular ASCII
                        // TODO: Graphicsmode?
                        cpm_conout(inp);
                        parse = 0;
                        break;
                    case 1: // Escape sequence
                        break;
                    case 2: // Escape Y, cursor addressing
                        mEsc = inp;
                        parse = 0;
                        break;
                    default: // Second part of cursor addressing
                        cur_x = inp - 32;
                        cur_y = mEsc - 32;
                        screen_setcursor(cur_x, cur_y);
                        parse = 0;
                        mEsc = 0;
                        break;
                }
            
            }
            if((parse == 1) && (inp != 0)) {
                screen_getcursor(&cur_x, &cur_y);
                switch(inp) {
                    case 0x0d:
                        cur_x = 0;
                        break;
                    case 0x0a:
                        cur_y++;
                        if(cur_y > h) {
                            cur_y = h;
                            screen_scrollup();
                        }
                        
                        break;
                    case 0x08:
                        cur_x--;
                        break;
                    case 0x09:
                        cur_x = cur_x + 8 - (cur_x % 8);
                        if(cur_x > w) cur_x = w;
                        break;
                    case 0x07:
                        // Bell, ignore
                        break;
                    case 0x1b:
                        // Escape
                        mEsc = 1;
                        break;
                    case 'A':
                        // Cursor up
                        mEsc = 0;
                        if(cur_y > 0) cur_y--;
                        break;
                    case 'B':
                        // Cursor down
                        mEsc = 0;
                        if(cur_y < h) cur_y++;
                        break;
                    case 'C':
                        // Cursor right
                        mEsc = 0;
                        if(cur_x < w) cur_x++;
                        break;
                    case 'D':
                        // Cursor left
                        mEsc = 0;
                        if(cur_x > 0 ) cur_x--;
                        break;
                    case 'F':
                        // Enter Graphics mode, ignore
                        mEsc = 0;
                        break;
                    case 'G':
                        // Exit graphics mode, ignore
                        mEsc = 0;
                        break;
                    case 'H':
                        // Cursor home
                        mEsc = 0;
                        cur_x = 0;
                        cur_y = 0;
                        break;
                    case 'I':
                        // Reverse line feed
                        mEsc = 0;
                        if(cur_y > 0)
                            cur_y--;
                        else {
                            cur_y = 0;
                            screen_scrolldown();
                        }
                        break;
                    case 'J':
                        // Erase to end of screen
                        mEsc = 0;
                        screen_clear_to_eol();
                        for(i=cur_y+1; i<h; i++) {
                            screen_setcursor(0,i);
                            screen_clear_to_eol();
                        }
                        break;
                    case 'K':
                        // Erase to end of line
                        mEsc = 0;
                        screen_clear_to_eol();
                        break;
                    case 'Y':
                        // Cursor addressing
                        mEsc = 2; 
                        break;
                    case 'Z':
                        // Identify terminal
                        mEsc = 0;
                        serial_out(0x1B);
                        serial_out('/');
                        serial_out('K');
                        break;
                    case '[':
                        // Enter hold screen mode, ignore
                        mEsc = 0;
                        break;
                    case '\\':
                        // Exit hold screen mode, igonre
                        mEsc = 0;
                        break;
                    case '=':
                        // Enter alternate keypad mode, ignore
                        mEsc = 0;
                        break;
                    case '>':
                        // Exit alternate keypad mode, ignore
                        mEsc = 0;
                        break;
                    default:
                        if((inp >= 32) && (inp < 127)) mEsc = 0;
                        break;
                }
                screen_setcursor(cur_x, cur_y);
            }
        } else {
            // Raw mode
            if(inp) cpm_conout(inp);
        }
        // Check for TTY input
        if(cpm_const()) {
            // Use cpm_bios_conin as cpm_conin crashes...
            inp = cpm_bios_conin();
            if(inp == 0x11) { // Ctrl+Q, check for local commands
                inp = cpm_bios_conin();
                switch(inp) {
                    case 'q':
                        // Quit
                        cpm_warmboot();
                        break;
                    case 'e':
                        // Toggle local echo
                        if(!local_echo) local_echo = 1;
                        else local_echo = 0;
                        break;
                    case 'v':
                        // Toggle VT52 emulation
                        if(!vt52) vt52 = 1;
                        else vt52 = 0;
                    default:
                    break;
                }
            } else {
                // Send data to serial port if found (echo?)
                if(local_echo) cpm_conout(inp); // Echo
                serial_out(inp);
            }
        }
    }   
}
