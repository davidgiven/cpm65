/*
 * DwarfStar - small editor with WordStar key bindings
 *
 * Copyright © 2024 by Ivo van Poorten
 *
 * BSD-2 License. See LICENSE file in root directory.
 *
 * Based on Build Your Own Text Editor
 * (https://viewsourcecode.org/snaptoken/kilo/)
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <cpm.h>
#include "lib/zmalloc.h"
#include "lib/screen.h"

#define ROUNDUP(x)  (((x)+7) & -8)  // nearest multiple of 8
#define MINSIZE 8                   // realloc doesn't free smaller than this

struct erow {
    int size;
    char *chars;
};

struct editorConfig {
    unsigned int cx, cy;
    unsigned int rowoff, coloff;
    uint8_t screenrows, screencols;
    unsigned int numrows;
    unsigned int rowsroom;
    struct erow *row;
    bool dirty;
    bool fullredraw;
} E;

#define STYLE_NORMAL 0
#define STYLE_REVERSE 1

#define ROOMINC 128      // increase room by x everytime we run out of rows

#define OUT_OF_MEMORY_STRING "Out of memory!"

#define CTRL(x) ((x)&0x1f)

void die(char *reason, bool clear) {
    if (clear) screen_clear();
    cpm_printstring(reason);
    cpm_printstring("\r\n");
    cpm_warmboot();
}

void __zfree_null(void) {
    die("zfree NULL", true);
}

bool validCharacter(uint8_t c) {
    return c >= ' ' && c <= '~';
}

// -------------------- ROW OPERATIONS --------------------

// Row operations with a bool return value return false when out of memory

bool editorInsertRow(int at, char *s, size_t len) {
    if (at < 0 || at > E.numrows) return true;

    void *tmp;
    if (E.numrows == E.rowsroom) {
        tmp = zrealloc(E.row, ROUNDUP(sizeof(struct erow) * (E.rowsroom + ROOMINC)));
        if (!tmp) return false;
        E.row = tmp;
        E.rowsroom += ROOMINC;
    }

    tmp = zmalloc(ROUNDUP(len + 1));
    if (!tmp) return false;

    memmove(&E.row[at+1], &E.row[at], sizeof(struct erow) * (E.numrows - at));

    E.row[at].chars = tmp;
    E.row[at].size = len;

    if (len) memcpy(E.row[at].chars, s, len);

    E.row[at].chars[len] = '\0';
    E.numrows++;

    E.fullredraw = true;

    return E.dirty = true;
}

void editorFreeRow(struct erow *row) {
    zfree(row->chars);
}

void editorDelRow(int at) {
    if (at < 0 || at >= E.numrows) return;
    editorFreeRow(&E.row[at]);
    memmove(&E.row[at], &E.row[at + 1], sizeof(struct erow) * (E.numrows - at - 1));
    E.numrows--;
    E.dirty = true;
    E.fullredraw = true;
}

bool editorRowInsertChar(struct erow *row, int at, uint8_t c) {
    if (at < 0 || at > row->size) at = row->size;

    void *tmp = zrealloc(row->chars, ROUNDUP(row->size + 2));
    if (!tmp) return false;

    row->chars = tmp;
    memmove(&row->chars[at + 1], &row->chars[at], row->size - at + 1);
    row->size++;
    row->chars[at] = c;

    return E.dirty = true;
}

bool editorRowAppendString(struct erow *row, char *s, size_t len) {
    void *tmp = zrealloc(row->chars, ROUNDUP(row->size + len + 1));
    if (!tmp) return false;
    row->chars = tmp;
    memcpy(&row->chars[row->size], s, len);
    row->size += len;
    row->chars[row->size] = '\0';
    return E.dirty = true;
}

void editorRowDelChar(struct erow *row, int at) {
    if (at < 0 || at >= row->size) return;
    memmove(&row->chars[at], &row->chars[at + 1], row->size - at);
    row->size--;        // xxx: zrealloc to free memory?
    E.dirty = true;;
}

// -------------------- EDITOR OPERATIONS --------------------

void editorDrawStatusMsg(char *msg);

void editorInsertChar(uint8_t c) {
    if (E.cy == E.numrows) {
        if (!editorInsertRow(E.numrows, "", 0)) goto failed;
    }
    if (!editorRowInsertChar(&E.row[E.cy], E.cx, c)) goto failed;
    E.cx++;
    return;

failed:
    editorDrawStatusMsg(OUT_OF_MEMORY_STRING);
}

void editorClearToEOL(struct erow *row) {
    row->size = E.cx;
    row->chars = zrealloc(row->chars, ROUNDUP(row->size + 1));
}

void editorInsertNewline(void) {
    if (E.cx == 0) {
        if (!editorInsertRow(E.cy, "", 0)) goto failed;
    } else {
        struct erow *row = &E.row[E.cy];
        if (!editorInsertRow(E.cy + 1, &row->chars[E.cx], row->size - E.cx))
            goto failed;
        row = &E.row[E.cy];   // reassign because zrealloc might have moved it
        editorClearToEOL(row);
        row->chars[row->size] = '\0';
    }
    E.cy++;
    E.cx = 0;
    return;

failed:
    editorDrawStatusMsg(OUT_OF_MEMORY_STRING);
}

void editorDelChar(void) {
    if (E.cy == E.numrows) return;
    if (E.cx == 0 && E.cy == 0) return;

    struct erow *row = &E.row[E.cy];
    if (E.cx > 0) {
        editorRowDelChar(row, E.cx - 1);
        E.cx--;
    } else {
        E.cx = E.row[E.cy - 1].size;
        if (!editorRowAppendString(&E.row[E.cy - 1], row->chars, row->size))
            goto failed;
        editorDelRow(E.cy);
        E.cy--;
    }
    return;

failed:
    editorDrawStatusMsg(OUT_OF_MEMORY_STRING);
}

void editorFindNextWord(void);

void editorDelWordRight(void) {
    unsigned int save_cx = E.cx, save_cy = E.cy;
    editorFindNextWord();
    if (E.cy != save_cy) {
        while (E.cx != 0) editorDelChar();
        editorDelChar();
        return;
    }
    while (E.cx != save_cx) editorDelChar();
}

// -------------------- FILE INPUT/OUTPUT --------------------

static inline uint8_t write_byte(FCB *fcb, uint8_t c, uint8_t *opos) {
    cpm_default_dma[*opos] = c;
    (*opos)++;
    if (*opos == 128) {
        if (cpm_write_sequential(fcb)) return 0xff;
        *opos = 0;
    }
    return 0;
}

uint8_t write_file(FCB *fcb) {
    fcb->ex = fcb->s1 = fcb->s2 = fcb->rc = 0;
    if (cpm_make_file(fcb)) return 0xff;
    fcb->cr = 0;

    cpm_set_dma(cpm_default_dma);

    uint8_t opos = 0;

    for (int j=0; j<E.numrows; j++) {
        for (int i=0; i<E.row[j].size; i++) {
            if (write_byte(fcb, E.row[j].chars[i], &opos)) return 0xff;
        }
        if (write_byte(fcb, '\r', &opos)) return 0xff;
        if (write_byte(fcb, '\n', &opos)) return 0xff;
    }
    if (write_byte(fcb, CTRL('Z'), &opos)) return 0xff;
    if (opos && cpm_write_sequential(fcb)) return 0xff;

    return cpm_close_file(fcb);
}

void editorSave(void) {
    cpm_fcb.ex = cpm_fcb.s1 = cpm_fcb.s2 = cpm_fcb.rc = 0;

    if (cpm_open_file(&cpm_fcb)) {
        editorDrawStatusMsg("Saving to new file...");
        if (write_file(&cpm_fcb)) editorDrawStatusMsg("Failed to save file");
        goto success;
    }

    editorDrawStatusMsg("Saving to temporary file...");

    static FCB tempfcb;
    strcpy((char *)tempfcb.f, "POUNDTMP$$$");
    tempfcb.dr = cpm_fcb.dr;
    if (write_file(&tempfcb)) {
        editorDrawStatusMsg("Failed to create temporary file");
        return;
    }

    editorDrawStatusMsg("Removing old file...");
    if (cpm_delete_file(&cpm_fcb)) {
        editorDrawStatusMsg("Unable to delete old file...");
        return;
    }

    editorDrawStatusMsg("Renaming temporary file...");
    memcpy(((uint8_t*)&tempfcb) + 16, &cpm_fcb, 16);
    if (cpm_rename_file((RCB*)&tempfcb)) {
        editorDrawStatusMsg("Renaming failed...");
        return;
    }

success:
    editorDrawStatusMsg("File saved");
    E.dirty = false;
}

char line[256];

void editorOpen(void) {
    cpm_fcb.cr = 0;
    if (cpm_open_file(&cpm_fcb)) return;    // new file

    cpm_set_dma(cpm_default_dma);

    uint8_t ipos = 128;
    uint8_t opos = 0;

    while (1) {
        if (ipos == 128) {
            ipos = 0;
            if (cpm_read_sequential(&cpm_fcb)) {
                if (cpm_errno == CPME_NOBLOCK) {
                    line[0] = CTRL('Z');
                } else {
                    die("Unable to read file", false);
                }
            }
        }
        uint8_t c = cpm_default_dma[ipos++];
        if (c == CTRL('Z')) break;
        if (c == CTRL('M')) continue;
        if (c == CTRL('J')) {
            if (!editorInsertRow(E.numrows, line, opos))
                die(OUT_OF_MEMORY_STRING, false);
            opos = 0;
            continue;
        }
        line[opos] = c;
        opos++;
        if (opos == 255) die("Maximum line length exceeded", false);
    }

    cpm_close_file(&cpm_fcb);
    E.dirty = false;
    line[0] = '\0';
}

// -------------------- FIND --------------------

const char *const findMsg = "Find: ";
char *findString = line + strlen(findMsg);
const uint8_t maxFindLen = 16;

void editorFindNext(void) {
    if (!findString[0]) return;
    unsigned int cx = E.cx, cy = E.cy;

    if (strstr(&E.row[cy].chars[cx], findString) == &E.row[cy].chars[cx]) cx++;

    while (cy != E.numrows) {
        char *match = strstr(&E.row[cy].chars[cx], findString);
        if (!match) {
            cx = 0;
            cy++;
            continue;
        }
        E.cy = cy;
        E.cx = match - E.row[cy].chars;
        break;
    }
}

void editorFind(void) {
    strcpy(line, findMsg);
    uint8_t p = 6, c, i = 0;
    while (1) {
        findString[i] = '\0';
        editorDrawStatusMsg(line);
        c = screen_waitchar();
        if (validCharacter(c) && i < maxFindLen) findString[i++] = c;
        if (i && (c == CTRL('H') || c == 127)) i--;
        if (!i && c == 27) break;
        if (c == 27) i = 0;
        if (c == 13) break;
    }
    editorDrawStatusMsg("");
    if (i) editorFindNext();
}

// -------------------- SCREEN OUTPUT --------------------

void editorScroll() {
    if (E.cy < E.rowoff) {
        E.rowoff = E.cy;
    }
    if (E.cy >= E.rowoff + E.screenrows) {
        E.rowoff = E.cy - E.screenrows + 1;
    }
    if (E.cx < E.coloff) {
        E.coloff = E.cx;
    }
    if (E.cx >= E.coloff + E.screencols) {
        E.coloff = E.cx - E.screencols + 1;
    }
}

void generateRuler(void) {
    char *p = line + 128;       // reuse buffer
    memset(p, '-', 80);
    for (int i = 0; i < 80; i += 8) p[i]='|';
    p[ 0] = 'L';
    p[79] = 'R';
    p[80] = 0;
}

void editorDrawRuler(void) {
    uint8_t i, c;
    screen_setcursor(0,0);
    screen_setstyle(STYLE_REVERSE);
    for (i=0; i<E.screencols; i++) {
        uint8_t c = line[128+E.coloff+i];
        if (!c) break;
        screen_putchar(c);
    }
    screen_setstyle(STYLE_NORMAL);
    if (i < E.screencols) screen_clear_to_eol();
}

void editorShowCursor(void) {
    screen_setcursor(E.cx - E.coloff, E.cy - E.rowoff + 1);
}

static const char *const dirty_string = " (modified)";

void editorDrawStatusBar() {
    uint8_t x, y, p;
    screen_setcursor(0, E.screenrows + 1);
    screen_setstyle(STYLE_REVERSE);
    p = 0;
    while (p<11) {
        if (cpm_fcb.f[p] != ' ') {
            screen_putchar(cpm_fcb.f[p]);
        }
        p++;
        if (p == 8 && cpm_fcb.f[p] != ' ') screen_putchar('.');
    }
    for (p = 0; E.dirty && p<strlen(dirty_string); p++)
        screen_putchar(dirty_string[p]);
    screen_getcursor(&x, &y);
    for ( ; x<E.screencols; x++)
        screen_putchar(' ');
    screen_setstyle(STYLE_NORMAL);
    editorShowCursor();
}

void editorDrawStatusMsg(char *msg) {
    screen_setcursor(0, E.screenrows + 2);
    for (int x = 0; x<E.screencols; x++) {
        if (!msg[x]) break;
        screen_putchar(msg[x]);
    }
    screen_clear_to_eol();
}

void editorRefreshLine(unsigned int y) {
    unsigned int filerow = y + E.rowoff, len, off;
    if (filerow >= E.numrows) {
        screen_setcursor(0,y+1);
        screen_putchar('~');
        screen_clear_to_eol();
    } else {
        screen_setcursor(0,y+1);

        if (E.cy - E.rowoff == y) {
            len = E.row[filerow].size - E.coloff;
            if (len < 0) len = 0;
            off = E.coloff;
        } else {
            len = E.row[filerow].size;
            off = 0;
        }
        if (len > E.screencols) len = E.screencols;

        for (int x=0; x<len; x++)
            screen_putchar(E.row[filerow].chars[off + x]);
        if (len != E.screencols) screen_clear_to_eol();
    }
}

void editorRefreshCursorLine(void) {
    editorRefreshLine(E.cy - E.rowoff);
    editorShowCursor();
}

void editorRefreshScreen(void) {
    screen_showcursor(0);
    for (unsigned int y=0; y<E.screenrows; y++) {
        editorRefreshLine(y);
    }
    editorShowCursor();
    screen_showcursor(1);
    E.fullredraw = false;
}

// -------------------- KEYBOARD INPUT --------------------

void editorFindPrevWord(void) {
    if (E.cx == 0) {
        if (E.cy == 0) return;
        E.cy--;
        E.cx = E.row[E.cy].size;
        return;
    }
    uint8_t i = E.cx - 1;
    while (i != 0 && E.row[E.cy].chars[i] == ' ') i--;
    while (i != 0 && E.row[E.cy].chars[i] != ' ') i--;
    if (i) i++;
    E.cx = i;
}

void editorFindNextWord(void) {
    if (E.cx == E.row[E.cy].size) {    // at eol
        if (E.cy != E.numrows) {
            E.cy++;
            E.cx = 0;
            E.coloff = 0;
            if (E.row[E.cy].chars[0] != ' ') return;
        }
    }
    if (E.cy == E.numrows) return;
    uint8_t i = E.cx;
    while (E.row[E.cy].chars[i] && E.row[E.cy].chars[i] != ' ') i++;
    while (E.row[E.cy].chars[i] && E.row[E.cy].chars[i] == ' ') i++;
    E.cx = i;
}

void editorSnapToRowlen(void) {
    struct erow *row = E.cy >= E.numrows ? NULL : &E.row[E.cy];
    int rowlen = row ? row->size : 0;
    if (E.cx > rowlen) E.cx = rowlen;
}

void editorMoveCursor(uint8_t key) {
    switch(key) {
    case SCREEN_KEY_LEFT:
    case CTRL('S'):     // left
        if (E.cx) {
            E.cx--;
        } else if (E.cy > 0) {
            E.cy--;
            E.cx = E.row[E.cy].size;
        }
        break;
    case SCREEN_KEY_RIGHT:
    case CTRL('D'): {    // right
            struct erow *row = E.cy >= E.numrows ? NULL : &E.row[E.cy];
            if (row && E.cx < row->size) {
                E.cx++;
            } else if (row && E.cx == row->size) {
                E.cy++;
                E.cx = 0;
            }
        }
        break;
    case SCREEN_KEY_UP:
    case CTRL('E'):     // up
        if (E.cy) E.cy--;
        break;
    case SCREEN_KEY_DOWN:
    case CTRL('X'):     // down
        if (E.cy < E.numrows) E.cy++;
        break;
    }

    editorSnapToRowlen();
}

void editorQuit(void) {
    if (E.dirty) {
        editorDrawStatusMsg("Quit without saving? (Y/N)");
        uint8_t c = screen_waitchar();
        if ((c & ~0x20) != 'Y') {
            editorDrawStatusMsg("");
            return;
        }
    }
    die("Done.", true);
}

void editorProcessKeypress(void) {
    static bool ctrlk = false, ctrlq = false, prevdirty = false;

    if (prevdirty != E.dirty) editorDrawStatusBar();
    prevdirty = E.dirty;

    uint8_t c = screen_waitchar();

    editorDrawStatusMsg("");

    if (ctrlk) {
        switch(c) {
        case 'q':
        case 'Q':
        case CTRL('Q'):                 // ^KQ Quit
            editorQuit();
            break;
        case 's':
        case 'S':
        case CTRL('S'):                 // ^KS Save
            editorSave();
            editorDrawStatusBar();
            break;
        }
        ctrlk = false;
        return;
    }

    if (ctrlq) {
        switch (c) {
        case 's':
        case 'S':
        case CTRL('S'):                 // ^QS to start of line
            E.cx = 0;
            break;
        case 'd':
        case 'D':
        case CTRL('D'):                 // ^QD to end of line
            if (E.cy < E.numrows)
                E.cx = E.row[E.cy].size;
            break;
        case 'r':
        case 'R':
        case CTRL('R'):                 // ^QR top of file
            E.cy = 0;
            break;
        case 'c':
        case 'C':
        case CTRL('C'):                 // ^QC end of file
            E.cy = E.numrows;
            break;
        case 'f':
        case 'F':
        case CTRL('F'):                 // ^QF find
            editorFind();
            break;
        case 'y':
        case 'Y':
        case CTRL('Y'):                 // ^QY clear to eol
            if (E.cy != E.numrows)
                editorClearToEOL(&E.row[E.cy]);
        }
        ctrlq = false;
        return;
    }

    switch (c) {
    case CTRL('M'):                     // ^M insert line break
        editorInsertNewline();
        break;

    case SCREEN_KEY_UP:
    case CTRL('E'):                     // ^E up
    case SCREEN_KEY_DOWN:
    case CTRL('X'):                     // ^X down
    case SCREEN_KEY_LEFT:
    case CTRL('S'):                     // ^S left
    case SCREEN_KEY_RIGHT:
    case CTRL('D'):                     // ^D right
        editorMoveCursor(c);
        break;

    case CTRL('R'):                     // ^R page up
    case CTRL('C'): {                   // ^C page down
            if (c == CTRL('R')) {
                E.cy = E.rowoff;
            } else {
                E.cy = E.rowoff + E.screenrows - 1;
                if (E.cy > E.numrows) E.cy = E.numrows;
            }
            int times = E.screenrows;
            while (times--)
                editorMoveCursor(c == CTRL('R') ? CTRL('E') : CTRL('X'));
        }
        E.fullredraw = true;
        break;

    case CTRL('A'):                     // ^A previous word
        editorFindPrevWord();
        break;
    case CTRL('F'):                     // ^F next word
        editorFindNextWord();
        break;

    case CTRL('W'):                     // ^W scroll up
        if (E.rowoff) E.rowoff--;
        break;
    case CTRL('Z'):                     // ^Z scroll down
        E.rowoff++;
        break;

    case CTRL('L'):                     // ^L find next
        editorFindNext();
        break;

    case 127:
    case CTRL('G'):                     // ^G DEL
    case CTRL('H'):                     // ^H BS
        if (c == CTRL('G')) editorMoveCursor(CTRL('D'));
        editorDelChar();
        break;

    case CTRL('T'):                     // ^T delete word right
        editorDelWordRight();
        break;

    case CTRL('Y'):                     // ^Y yank line
        editorDelRow(E.cy);
        editorSnapToRowlen();
        break;

    case CTRL('K'):                     // start ^K compound command
        ctrlk = true;
        break;
    case CTRL('Q'):                     // start ^Q compound command
        ctrlq = true;
        break;

    case CTRL('I'): {                   // ^I TAB
            int n = 4 - (E.cx & 3);
            for (uint8_t i=0; i < n; i++) editorInsertChar(' ');
            break;
        }
    default:
        if (validCharacter(c)) editorInsertChar(c);
        break;
    }
}

// -------------------- INIT --------------------

void initEditor(void) {
    if (!screen_init()) die("No SCREEN", false);

    uint16_t tpa = cpm_bios_gettpa();
    uint8_t *top = (uint8_t *) (tpa & 0xff00);
//    zmalloc_init(cpm_ram, 4096, MINSIZE);        // test low RAM
    zmalloc_init(cpm_ram, top - cpm_ram, MINSIZE);

    screen_getsize(&E.screencols, &E.screenrows);
    E.screencols++;
    E.screenrows-=2;
    E.cx = E.cy = E.rowoff = E.coloff = E.numrows = E.rowsroom = 0;
    E.row = NULL;
    E.dirty = false;
    E.fullredraw = true;
}

// -------------------- MAIN --------------------

void main(void) {
    initEditor();
    editorOpen();
    generateRuler();
    editorDrawRuler();
    editorDrawStatusBar();
    editorDrawStatusMsg("Welcome to DwarfStar...");

    while(1) {
        if (E.fullredraw) editorRefreshScreen();
        else editorRefreshCursorLine();

        unsigned int prev_cy = E.cy;
        unsigned int prev_coloff = E.coloff, prev_rowoff = E.rowoff;

        editorProcessKeypress();
        editorScroll();

        if (E.coloff != prev_coloff) editorDrawRuler();

        if (E.rowoff != prev_rowoff) {
            E.fullredraw = true;
            continue;
        }

        if (E.cy != prev_cy) {
            unsigned int save_cx = E.cx, save_cy = E.cy;
            E.cx = 0;
            E.cy = prev_cy;
            editorScroll();
            editorRefreshCursorLine();
            E.cx = save_cx;
            E.cy = save_cy;
            editorScroll();
        }
    }
}
