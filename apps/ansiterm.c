/* ansiterm - Copyright (c) Henrik Löfgren
 * This program is redistributable under the terms of the 2-clause BSD license.
 * See LICENSE in the distribution root directory for more information
 *
 * An ANSI/VT100 and VT52 terminal emulator for CP/M-65. 
 * The ANSI mode is rather bare bones, while the VT52 mode supports most commands.
 * It works well enough to login and run vim on a linux server in both ANSI/VT100 and
 * VT52 mode (if the shell is configured correctly for VT52).
 * Xmodem file transfer during a session using sx/rx on linux works.
 *
 * Requires SERIAL driver. SCREEN driver needed for terminal emulation, only RAW mode
 * available when no SCREEN driver is found.
 * 
 * VT52 parsing code heavily inspired by Kenneth Gobers VT52 terminal emulator for 
 * windows, see https://github.com/kgober/VT52/
 *
 * Xmodem code heavily inspired by xrecv.asm
 *
 * Commands:
 * Ctrl-q + q   -   Quit
 * Ctrl-q + e   -   Local echo on/off (default off)
 * Ctrl-q + m   -   Cycle between ANSI/VT52/RAW mode (default is ANSI)
 * Ctrl-q + r   -   Xmodem receive
 * Ctrl-q + s   -   Xmodem send
 *
 * TODO:
 * Implement sending ANSI/VT52 sequences for arrow keys (needs updated screen driver)
 * Implement port settings (needs updated serial driver)
 * Implement XON/XOFF flow control (or should it be handled by the driver?)
 */
 
#include <cpm.h>
#include <stdio.h>
#include "lib/serial.h"
#include "lib/screen.h"
#include "lib/printi.h"

#define ESC         0x1b
#define BELL        0x07
#define BACKSPACE   0x08
#define TAB         0x09
#define CR          0x0d
#define LF          0x0a
#define VT          0x0b
#define FF          0x0c
#define LOCAL_CMD   0x11   // ctrl+q
#define SOH         0x01
#define EOT         0x04
#define ACK         0x06
#define DLE         0x10
#define XON         0x11
#define XOFF        0x13
#define NAK         0x15
#define SYN         0x16
#define CAN         0x18
#define SUB         0x1a

static uint8_t mEsc = 0;
static uint8_t w;
static uint8_t h;

static FCB xmodem_file;
static uint8_t xmodem_buffer[128]; 

typedef enum {
    C0,
    ESCAPE,
    CSI,
    VT52_MODE
} a_state;

typedef enum {
    RAW,
    VT52,
    ANSI
} t_mode;

static a_state ansi_state = C0;
static uint8_t CSI_param[2];
static uint8_t CSI_param_pos;
static uint8_t CSI_num_pos;
static uint8_t CSI_private;
static uint8_t saved_x=0;
static uint8_t saved_y=0;

static void vt52_parse(uint8_t inp) {
    uint8_t parse;
    uint8_t cur_x;
    uint8_t cur_y;  
    uint8_t i;  
    parse = 1;
    screen_getcursor(&cur_x, &cur_y);
    
    if((inp >= 32) && (inp < 127)) {
        switch(mEsc) {
            case 0: // Regular ASCII
                screen_putchar(inp);
                cur_x++;
                if(cur_x > w) cur_x = 0;
                screen_setcursor(cur_x,cur_y);
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
        switch(inp) {
            case CR:
                cur_x = 0;
                break;
            case LF:
                cur_y++;
                if(cur_y > h) {
                    cur_y = h;
                    screen_scrollup();
                }
                break;
            case BACKSPACE:
                cur_x--;
                break;
            case TAB:
                cur_x = cur_x + 8 - (cur_x % 8);
                if(cur_x > w) cur_x = w;
                break;
            case BELL:
                // Bell, ignore
                break;
            case ESC:
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
            case '<':
                // Exit VT52-mode (return to ANSI)
                mEsc = 0;
                ansi_state = C0;
                break;
            default:
                if((inp >= 32) && (inp < 127)) mEsc = 0;
                break;
        }
        screen_setcursor(cur_x, cur_y);
    }
}

static void ansi_parse(uint8_t inp) {
    uint8_t cur_x;
    uint8_t cur_y;
    uint8_t i;
    screen_getcursor(&cur_x, &cur_y);
 
    switch(ansi_state) {
        case C0:
            if(inp >=32 && (inp < 127)) {
                // Regular ASCII text
                screen_putchar(inp);
                cur_x++;
                if(cur_x > w) cur_x = 0;
            } else {
                // Parse C0 codes
                switch(inp) {
                    case BELL:
                        // Ignore bell
                        break;
                    case BACKSPACE:
                        cur_x--;
                        break;
                    case TAB:
                        cur_x = cur_x + 8 - (cur_x % 8);
                        if(cur_x > w) cur_x = w;
                        break;
                    case LF:
                    case VT:
                        cur_y++;
                        if(cur_y > h) {
                            cur_y = h;
                            screen_scrollup();
                        }
                        break;
                    case CR:
                        cur_x = 0;
                        break;
                    case FF:
                        // Form feed, ignore
                        break;
                    case ESC:
                        ansi_state = ESCAPE;
                    default:
                        break;     
                }
                screen_setcursor(cur_x, cur_y);
            }
            break;
        case ESCAPE:
            if(inp == '[') {
                // CSI sequence, prepare for parsing
                //cpm_printstring("CSI!\r\n");
                CSI_param[0] = 0;
                CSI_param[1] = 0;
                CSI_param_pos = 0;
                CSI_num_pos = 0;
                CSI_private = 0;
                ansi_state = CSI;
            } else if(inp == ']') {
                // OSC sequence, ignore for now
                // Must probably be handled or at least ignored in a proper way
                ansi_state = C0;
            } else if ((inp >= 0x30) && (inp <=0x3F)) {
                // Fp sequences
                // Save cursor, DEC
                if (inp == '7') {
                    saved_x = cur_x;
                    saved_y = cur_y;
                }
                // Restore cursor, DEC
                if (inp == '8') {
                    cur_x = saved_x;
                    cur_y = saved_y;
                }
                ansi_state = C0;
            } else {
                // Ignore anything else
                ansi_state = C0;
            }
            break;
        case CSI:
            if((inp >=0x30) && (inp <= 0x39)) {
                // Numerical input
                if(CSI_param_pos < 2) // No supported commands have more than 2 args
                    CSI_param[CSI_param_pos] = CSI_param[CSI_param_pos]*10*CSI_num_pos
                                               + (inp - 0x30);
                CSI_num_pos++;
            } else if(inp == ';') {
                // Argument separator
                CSI_param_pos++;
                CSI_num_pos = 0;
            } else if(inp == '?') {
                // Private command
                CSI_private = 1;
            } else if((inp >= 0x20) && (inp <= 0x20)) {
                // Ignore other intermediate symbols
                ansi_state = CSI;
            } else if((inp >= 0x40) && (inp <= 0x7E)) {
                // Parse commands
                switch(inp) {
                    case 'A':
                        // Cursor up
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        if(cur_y < CSI_param[0]) cur_y = 0;
                        else cur_y -= CSI_param[0];
                        break;
                    case 'B':
                        // Cursor down
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        if((h - cur_y) < CSI_param[0]) cur_y = h;
                        else cur_y += CSI_param[0];
                        break;
                    case 'C':
                        // Cursor right
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        if((w - cur_x) < CSI_param[0]) cur_x = w;
                        else cur_x += CSI_param[0];
                        break;
                    case 'D':
                        // Cursor left
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        if(cur_x < CSI_param[0]) cur_x = 0;
                        else cur_x -= CSI_param[0];
                        break;
                    case 'E':
                        // Cursor next line
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        if((h - cur_y) < CSI_param[0]) cur_y = h;
                        else cur_y += CSI_param[0];
                        cur_x = 0;
                        break;
                    case 'F':
                        // Cursor previous line
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        if(cur_y < CSI_param[0]) cur_y = 0;
                        else cur_y -= CSI_param[0];
                        cur_x = 0;
                        break;
                    case 'G':
                        // Cursor horizontal absolute
                        if(CSI_param[0] > 0) CSI_param[0]--;
                        if(CSI_param[0] > w) CSI_param[0] = w;
                        cur_x = CSI_param[0];
                        break;
                    case 'H':
                    case 'f':
                        // Cursor Position and HVP
                        if(CSI_param[0] > 0) CSI_param[0]--;
                        if(CSI_param[0] > h) CSI_param[0] = h;
                        
                        if(CSI_param[1] > 0) CSI_param[1]--;
                        if(CSI_param[1] > w) CSI_param[1] = w;
                        
                        cur_x = CSI_param[1];
                        cur_y = CSI_param[0];
                        break;
                    case 'J':
                        // Erase in display
                        if(CSI_param[0]==0) {
                            // Clear to end of screen
                            screen_clear_to_eol();
                            for(i=cur_y+1; i<h; i++) {
                                screen_setcursor(0, i);
                                screen_clear_to_eol();
                            }
                        } else if(CSI_param[0]==1) {
                            // Clear to beginning of screen
                            for(i=0; i<cur_x; i++) {
                                screen_setcursor(i, cur_y);
                                screen_putchar(' ');
                            }
                            for(i=0; i<cur_y; i++) {
                                screen_setcursor(0, i);
                                screen_clear_to_eol();
                            }
                        } else {
                            // Clear entire screen
                            screen_clear();
                        }
                    case 'K':
                        // Erase in line
                        if(CSI_param[0]==0) {
                            // Clear to end of line
                            screen_clear_to_eol();                 
                        } else if(CSI_param[0]==1) {
                            // Clear to beginning of line
                            for(i=0; i<cur_x; i++) {
                                screen_setcursor(i, cur_y);
                                screen_putchar(' ');
                            }
                        } else if(CSI_param[0]==2) {
                            // Clear entire line
                            screen_setcursor(0, cur_y);
                            screen_clear_to_eol();
                        }
                        break;
                    case 'S':
                        // Scroll up
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
                        
                        for(i=0; i<CSI_param[0]; i++)
                            screen_scrollup();

                        break;
                    case 'T':
                        // Scroll down
                        if(CSI_param[0] == 0) CSI_param[0] = 1;
    
                        for(i=0; i<CSI_param[0]; i++) {
                            screen_scrolldown();
                        }
                    
                        break;
                    case 'm':
                        // Select Graphic Rendition
                        // Only support for inverted text in SCREEN driver
                        if((CSI_param[0] == 0) && (CSI_param[1]==0)) {
                            // Normal formatting
                            screen_setstyle(0);
                        } else if((CSI_param[0] == 7) || (CSI_param[1] == 7)) {
                            // Inverse
                            screen_setstyle(1);
                        } else if(CSI_param[0] == 27) {
                            // Turn off inverse
                            screen_setstyle(0);
                        }
                        break;
                    case 's':
                        // Save cursor position, SCO code
                        saved_x = cur_x;
                        saved_y = cur_y;
                        break;
                    case 'u':
                        // Restore saved cursor position, SCO code
                        cur_x = saved_x;
                        cur_y = saved_y;
                        break;
                    case 'n':
                        // Device status report
                        // TODO: ASCII conversion of cursor position, send 0 for now
                        serial_outp(ESC);
                        serial_outp('[');
                        serial_outp('0');
                        serial_outp(';'); 
                        serial_outp('0');
                        serial_outp('R');
                        break;
                    case 'l':
                        // Enter VT52 mode
                        if(CSI_param[0] == 2)
                            ansi_state = VT52_MODE;
                        // Make cursor invisible
                        if(CSI_param[0] == 25)
                            screen_showcursor(0);
                        // Ignore other private commands
                        break; 
                    case 'h':
                        if(CSI_param[0] == 25)
                            screen_showcursor(1);
                        // Ignore other private commands
                        
                        break;               
                    default:
                        break;
                }
                if(ansi_state == CSI)
                    ansi_state = C0;
                
                screen_setcursor(cur_x, cur_y);
            } else {
                // Ignore invalid commands, abort
                ansi_state = C0;
            }
            break;
        case VT52_MODE:
            // In VT52-mode
            vt52_parse(inp);
            break;
        default:
            ansi_state = C0;
            break;
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

static uint8_t getblockchar(uint8_t *data) {
    uint8_t data_available;
    uint16_t i;
    for(i=0; i<30000; i++) {
        serial_inp(data, &data_available);
        if(data_available) break;
    }
    return data_available;
}

static void xmodem_receive(void) {
    char filename_input[14];
    uint8_t block_cnt;
    uint8_t block_exp = 1;
    uint8_t pos = 0;
    uint8_t checksum;
    uint8_t inp;
    uint8_t outp;
    uint8_t data_available;
    
    cpm_printstring("X modem receive");
    cr();
    cpm_printstring("Enter filename: ");

    filename_input[0]=13;
    filename_input[1]=0;    
    cpm_readline((uint8_t *)filename_input);
    cr();

    // Reset FCB
    xmodem_file = (const FCB){0}; 
    
    // Parse filename
    cpm_set_dma(&xmodem_file);
    if(!cpm_parse_filename(&filename_input[2])) {
        cpm_printstring("Bad filename\r\n");
        return;
    }

    // Create file
    if(cpm_make_file( &xmodem_file)) {
        cpm_printstring("Error creating file\r\n");
        return;
    }

    cpm_printstring("Waiting for sender");
    cr();
    cpm_printstring("Press any key to cancel");
    cr(); 
    outp = NAK;
    // Transmission
    while(1) {
        serial_out(outp);
        if(getblockchar(&inp)) {
            if(inp == EOT) {
                cr();
                cpm_printstring("Transmission done");
                cr();
                cpm_close_file(&xmodem_file);
                return;
            }
            if(inp == CAN) {
                cr();
                cpm_printstring("Transmission cancelled");
                cr();
                cpm_close_file(&xmodem_file);
                return;
            }
            if(inp == SOH) {
                // Got header, get package
                outp = NAK;
                checksum = 0;
                getblockchar(&inp);
                block_cnt = inp;
                getblockchar(&inp);
                if((block_cnt == (inp ^ 0xFF)) && (block_cnt == block_exp)) {
                    // Get block, otherwise retry
                    for(pos=0; pos<128; pos++) {
                        getblockchar(&inp);
                        xmodem_buffer[pos]=inp;
                        checksum += inp;                    
                    }
                    // Verify checksum
                    getblockchar(&inp);
                    if(checksum == inp) {
                        outp = ACK;
                        cpm_set_dma(&xmodem_buffer);
                        cpm_write_sequential(&xmodem_file);
                        printi(block_cnt);    
                    }
                    block_exp++;
                }
            } 
        }
        cpm_conout('.');
        if(cpm_const()) {
            cpm_close_file(&xmodem_file);
            return;
        }
    }

}

static void xmodem_send_block(uint8_t block_cnt) {
    uint8_t i;
    uint8_t checksum;
    uint8_t data;
    
    // Print block number
    printi(block_cnt);

    // Send header
    serial_outp(SOH);
    serial_outp(block_cnt);
    serial_outp(block_cnt ^ 0xFF);

    checksum = 0;
    // Send data
    for(i=0; i<128; i++) {
        data = xmodem_buffer[i];
        checksum += data;
        serial_outp(data);
    }

    // Send checksum
    serial_outp(checksum);    
}

static void xmodem_send(void) {
    char filename_input[14];
    uint8_t block_cnt = 1;
    uint8_t pos = 0;
    uint8_t delay;
    uint8_t inp;
    uint8_t outp;
    uint8_t nak_cnt = 0;
    
    cpm_printstring("X modem send");
    cr();
    cpm_printstring("Enter filename: ");

    filename_input[0]=13;
    filename_input[1]=0;    
    cpm_readline((uint8_t *)filename_input);
    cr();

    // Reset FCB
    xmodem_file = (const FCB){0};
    
    // Parse filename
    cpm_set_dma(&xmodem_file);
    if(!cpm_parse_filename(&filename_input[2])) {
        cpm_printstring("Bad filename\r\n");
        return;
    }

    // Open file
    if(cpm_open_file( &xmodem_file)) {
        cpm_printstring("Error opening file\r\n");
        return;
    }

    // Load first block
    cpm_set_dma(&xmodem_buffer);
    cpm_read_sequential(&xmodem_file);

    cpm_printstring("Waiting for receiver...");
    cr();
    cpm_printstring("Press any key to cancel");
    cr();

    while(1) {
        if(getblockchar(&inp)) {
            if(inp == NAK) {
                // Resend block
                xmodem_send_block(block_cnt);
                nak_cnt++;
                if(nak_cnt == 11) {
                    cpm_printstring("Too many NAKs, aborting");
                    cr();
                    serial_outp(CAN);
                    cpm_close_file(&xmodem_file);
                    return;
                }
            }
            if(inp == ACK) {
                cpm_conout('.');
                // Load next block
                cpm_set_dma(&xmodem_buffer);
                if(cpm_read_sequential(&xmodem_file)) {
                    cr();
                    cpm_printstring("Transmission done");
                    cr();
                    serial_outp(EOT);
                    cpm_close_file(&xmodem_file);
                    return;
                }
                block_cnt++;
                // Send next block
                xmodem_send_block(block_cnt);
            }    
        }
        if(cpm_const()) {
            // Cancel due to keypress
            cpm_close_file(&xmodem_file);
            serial_outp(CAN);
            return;
        }
    }
}

int main(void) 
{
    uint8_t inp;
    uint8_t data_available;
    uint8_t local_echo = 0;
    t_mode term_mode = ANSI;
    uint8_t screen_available = 1;
    
    if(!serial_init())
        fatal("No SERIAL driver, exiting");

    if(!screen_init()) {
        cpm_printstring("No SCREEN driver, ANSI and VT52 mode disabled");
        cr();
        term_mode = RAW;
        screen_available = 0;
    }
    // Open serial port
    serial_open(0);
    
    cpm_printstring("ANSI/VT100 and VT52 terminal emulator");
    cr();
    cpm_printstring("Press ctrl-q + h for help");
    cr();
    
    if(screen_available) screen_getsize(&w, &h);
    
    while(1) { 
        inp = 0;
        // Check for data on serial port and parse it
        serial_inp(&inp, &data_available);
        if(term_mode == ANSI && data_available) {
            ansi_parse(inp);
        } else if(term_mode == VT52 && data_available) {
            vt52_parse(inp); 
        } else {
            // Raw mode
            if(data_available) cpm_conout(inp);
        }
        // Check for TTY input
        if(cpm_const()) {
            // Use cpm_bios_conin as cpm_conin crashes...
            inp = cpm_bios_conin();
            if(inp == LOCAL_CMD) { // Ctrl+Q, check for local commands
                inp = cpm_bios_conin();
                cr();
                switch(inp) {
                    case 'q':
                    case 'Q':
                        // Quit
                        cpm_printstring("Goodbye!");
                        cr();
                        serial_close();
                        cpm_warmboot();
                        break;
                    case 'e':
                    case 'E':
                        // Toggle local echo
                        cpm_printstring("Local echo ");
                        if(!local_echo) {
                            local_echo = 1;
                            cpm_printstring("ON");
                        } else { 
                            local_echo = 0;
                            cpm_printstring("OFF");
                        }
                        cr();
                        break;
                    case 'm':
                    case 'M':
                        // Toggle terminal emulation mode
                        cpm_printstring("Terminal emulation mode: ");
                        if(term_mode == ANSI && screen_available) {
                            term_mode = VT52;
                            cpm_printstring("VT52");
                        } else if(term_mode == RAW && screen_available) {
                            term_mode = ANSI;
                            cpm_printstring("ANSI");
                        } else { 
                            term_mode = RAW;
                            cpm_printstring("Raw");
                        }
                        cr();
                        break;
                    case 'r':
                    case 'R':
                        // Xmodem receive;
                        xmodem_receive();
                        break;
                    case 's':
                    case 'S':
                        // Xmodem send
                        xmodem_send();
                        break;
                    case 'h':
                    case 'H':
                        // Print help
                        cpm_printstring("Available commands:");
                        cr();
                        cpm_printstring("Ctrl-q + q:    Quit");
                        cr();
                        cpm_printstring("Ctrl-q + e:    Toggle local echo");
                        cr();
                        cpm_printstring("Ctrl-q + m:    Cycle emulation mode");
                        cr();
                        cpm_printstring("Ctrl-q + r:    Xmodem Receive");
                        cr();
                        cpm_printstring("Ctrl-q + s:    Xmodem Send");
                        cr();
                        break;
                    default:
                    break;
                }
            } else {
                // Send data to serial port and echo if avtivated
                if(local_echo) cpm_conout(inp);
                serial_out(inp);
            }
        }
    }   
}
