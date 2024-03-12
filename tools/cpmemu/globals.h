#ifndef GLOBALS_H
#define GLOBALS_H

#include <stdbool.h>
#include "third_party/lib6502/lib6502.h"

#define TPA_BASE 0x0200
#define ZP_BASE 0x00
#define ZP_END 0x00
#define BDOS_ADDRESS 0xff00
#define BIOS_ADDRESS 0xff01
#define EXIT_ADDRESS 0xff02

extern M6502* cpu;
extern uint8_t ram[0x10000];
extern uint16_t himem;
extern bool tracing;

extern void emulator_init(void);
extern void emulator_run(void);
extern void showregs(void);

extern const uint8_t ccp_data[];
extern const int ccp_len;

extern const uint8_t biosbdosdata_data[];
extern const int biosbdosdata_len;

extern void bios_coldboot(void);
extern void bios_warmboot(void);

extern void bdos_entry(uint8_t bdos_call, bool log);
extern void bios_entry(uint8_t bios_call);

typedef struct
{
	uint8_t drive;
	char bytes[11];
}
cpm_filename_t;

extern bool parse_fcb(uint8_t fcb[16], const char* filename);

extern void files_init(void);
extern void file_set_drive(int drive, const char* path);
extern struct file* file_open(cpm_filename_t* filename);
extern struct file* file_create(cpm_filename_t* filename);
extern int file_close(cpm_filename_t* filename);
extern int file_read(struct file* file, uint8_t* data, uint16_t record);
extern int file_write(struct file* file, uint8_t* data, uint16_t record);
extern int file_getrecordcount(struct file* f);
extern void file_setrecordcount(struct file* f, int count);
extern int file_findfirst(cpm_filename_t* pattern);
extern int file_findnext(cpm_filename_t* result);
extern int file_delete(cpm_filename_t* pattern);
extern int file_rename(cpm_filename_t* src, cpm_filename_t* dest);

extern void fatal(const char* message, ...);

extern bool flag_enter_debugger;
extern char* const* user_command_line;

#endif

