#define _POSIX_C_SOURCE 199309
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <readline/readline.h>
#include <readline/history.h>
#include "globals.h"

M6502* cpu;
uint8_t ram[0x10000];
bool breakpoints[0x10000];

struct watchpoint
{
    uint16_t address;
    uint8_t value;
    bool enabled;
};

static struct watchpoint watchpoints[16];
bool tracing = false;
static bool singlestepping = true;
static bool bdosbreak = false;
static bool bdoslog = false;

void showregs(void)
{
    char buffer[64];
    M6502_dump(cpu, buffer);
    printf("%s\n", buffer);

    int bytes = M6502_disassemble(cpu, cpu->registers->pc, buffer);
    printf("%04x : ", cpu->registers->pc);
	for (int i=0; i<3; i++)
	{
		if (i < bytes)
			printf("%02x ", ram[cpu->registers->pc + i]);
		else
			printf("   ");
	}
	printf(": %s\n", buffer);
}

static void cmd_register(void)
{
    char* w1 = strtok(NULL, " ");
    char* w2 = strtok(NULL, " ");

    if (w1 && w2)
    {
        uint16_t value = strtoul(w2, NULL, 16);

        if (strcmp(w1, "sp") == 0)
            cpu->registers->s = value;
        else if (strcmp(w1, "pc") == 0)
            cpu->registers->pc = value;
        else if (strcmp(w1, "p") == 0)
            cpu->registers->p = value;
        else if (strcmp(w1, "a") == 0)
            cpu->registers->a = value;
        else if (strcmp(w1, "x") == 0)
            cpu->registers->x = value;
        else if (strcmp(w1, "y") == 0)
            cpu->registers->y = value;
        else
        {
            printf("Bad register\n");
            return;
        }
    }

    showregs();
}

static int break_cb(M6502* cpu, uint16_t address, uint8_t data)
{
    singlestepping = true;
    return address;
}

static void cmd_break(void)
{
    char* w1 = strtok(NULL, " ");
    if (w1)
    {
        uint16_t breakpc = strtoul(w1, NULL, 16);
        breakpoints[breakpc] = true;
    }
    else
    {
        for (int i = 0; i < 0x10000; i++)
        {
            if (breakpoints[i])
                printf("%04x\n", i);
        }
    }
}

static void cmd_delete_breakpoint(void)
{
    char* w1 = strtok(NULL, " ");
    if (w1)
    {
        uint16_t breakpc = strtoul(w1, NULL, 16);
        breakpoints[breakpc] = false;
    }
}

static void cmd_watch(void)
{
    char* w1 = strtok(NULL, " ");
    if (w1)
    {
        uint16_t watchaddr = strtoul(w1, NULL, 16);
        for (int i = 0; i < sizeof(watchpoints) / sizeof(*watchpoints); i++)
        {
            struct watchpoint* w = &watchpoints[i];
            if (!w->enabled)
            {
                w->address = watchaddr;
                w->enabled = true;
                w->value = ram[watchaddr];
                return;
            }
        }
        printf("Too many breakpoints\n");
    }
    else
    {
        for (int i = 0; i < sizeof(watchpoints) / sizeof(*watchpoints); i++)
        {
            struct watchpoint* w = &watchpoints[i];
            if (w->enabled)
                printf("%04x (current value: %02x)\n", w->address, w->value);
        }
    }
}

static void cmd_delete_watchpoint(void)
{
    char* w1 = strtok(NULL, " ");
    if (w1)
    {
        uint16_t address = strtoul(w1, NULL, 16);
        for (int i = 0; i < sizeof(breakpoints) / sizeof(*breakpoints); i++)
        {
            struct watchpoint* w = &watchpoints[i];
            if (w->enabled && (w->address == address))
            {
                w->enabled = false;
                return;
            }
        }
        printf("No such watchpoint\n");
    }
}

static void cmd_memory(void)
{
    char* w1 = strtok(NULL, " ");
    char* w2 = strtok(NULL, " ");

    if (!w2)
        w2 = "100";

    if (w1 && w2)
    {
        uint16_t startaddr = strtoul(w1, NULL, 16);
        uint16_t endaddr = startaddr + strtoul(w2, NULL, 16);
        uint16_t startrounded = startaddr & ~0xf;
        uint16_t endrounded = (endaddr + 0xf) & ~0xf;

        uint16_t p = startrounded;

        while (p < endrounded)
        {
            printf("%04x : ", p);
            for (int i = 0; i < 16; i++)
            {
                uint16_t pp = p + i;
                if ((pp >= startaddr) && (pp < endaddr))
                    printf("%02x ", ram[pp]);
                else
                    printf("   ");
            }
            printf(": ");
            for (int i = 0; i < 16; i++)
            {
                uint16_t pp = p + i;
                if ((pp >= startaddr) && (pp < endaddr))
                {
                    uint8_t c = ram[pp];
                    if ((c < 32) || (c > 127))
                        c = '.';
                    putchar(c);
                }
                else
                    putchar(' ');
            }
            p += 16;
            putchar('\n');
        }
    }
}

static void cmd_unassemble(void)
{
    char* w1 = strtok(NULL, " ");
    char* w2 = strtok(NULL, " ");

    if (!w2)
        w2 = "10";

    if (w1 && w2)
    {
        uint16_t addr = strtoul(w1, NULL, 16);
        uint16_t endaddr = addr + strtoul(w2, NULL, 16);

        while (addr < endaddr)
        {
            char buffer[64];
            int len = M6502_disassemble(cpu, addr, buffer);
            printf("%04x : ", addr);
			for (int i=0; i<3; i++)
			{
				if (i < len)
					printf("%02x ", ram[addr + i]);
				else
					printf("   ");
			}
            printf(": %s\n", buffer);

            addr += len;
        }
    }
}

static void cmd_bdos(void)
{
    char* w1 = strtok(NULL, " ");
    if (w1)
    {
        bdosbreak = !!strtoul(w1, NULL, 16);
        bdoslog = bdosbreak || (toupper(*w1) == 'L');
    }

    printf("break on bdos entry: %s\n", bdosbreak ? "on" : "off");
    printf("log on bdos entry: %s\n", bdoslog ? "on" : "off");
}

static void cmd_tracing(void)
{
    char* w1 = strtok(NULL, " ");
    if (w1)
        tracing = !!strtoul(w1, NULL, 16);
    else
        printf("tracing: %s\n", tracing ? "on" : "off");
}

static void cmd_help(void)
{
    printf(
        "Sleazy debugger\n"
        "  r               show registers\n"
        "  r <reg> <value> set register\n"
        "  b               show breakpoints\n"
        "  b <addr>        set breakpoint\n"
        "  db <addr>       delete breakpoint\n"
        "  w <addr>        set watchpoint\n"
        "  dw <addr>       delete watchpoint\n"
        "  m <addr> <len>  show memory\n"
        "  u <addr> <len>  unassemble memory\n"
        "  s               single step\n"
        "  g               continue\n"
        "  bdos 0|1|L      enable break/log on bdos entry\n"
        "  trace 0|1       enable tracing\n");
}

static void debug(void)
{
    bool go = false;
    showregs();
    while (!go)
    {
        char* cmdline = readline("debug>");
        if (!cmdline)
            exit(0);

        char* token = strtok(cmdline, " ");
        if (token != NULL)
        {
            if (strcmp(token, "?") == 0)
                cmd_help();
            else if (strcmp(token, "r") == 0)
                cmd_register();
            else if (strcmp(token, "b") == 0)
                cmd_break();
            else if (strcmp(token, "db") == 0)
                cmd_delete_breakpoint();
            else if (strcmp(token, "w") == 0)
                cmd_watch();
            else if (strcmp(token, "dw") == 0)
                cmd_delete_watchpoint();
            else if (strcmp(token, "m") == 0)
                cmd_memory();
            else if (strcmp(token, "u") == 0)
                cmd_unassemble();
            else if (strcmp(token, "s") == 0)
            {
                singlestepping = true;
                go = true;
            }
            else if (strcmp(token, "g") == 0)
            {
                singlestepping = false;
                go = true;
            }
            else if (strcmp(token, "bdos") == 0)
                cmd_bdos();
            else if (strcmp(token, "trace") == 0)
                cmd_tracing();
            else
                printf("Bad command\n");
        }

        free(cmdline);
    }
}

static int rts(void)
{
    uint16_t pc;
    pc = (uint16_t)ram[++cpu->registers->s + 0x100];
    pc |= (uint16_t)ram[++cpu->registers->s + 0x100] << 8;
    cpu->registers->pc = pc + 1;
}

static void sigusr1_cb(int number)
{
    singlestepping = true;
}

void emulator_init(void)
{
	memset(ram, 0xee, sizeof(ram));

    cpu = M6502_new(NULL, ram, NULL);
    singlestepping = flag_enter_debugger;

    struct sigaction action = {.sa_handler = sigusr1_cb};
    sigaction(SIGUSR1, &action, NULL);
}

void emulator_run(void)
{
    for (;;)
    {
        uint16_t pc = cpu->registers->pc;
        singlestepping |= breakpoints[pc];

        if ((pc < BDOS_ADDRESS) && (ram[pc] == 0))
            singlestepping = true;

        for (int i = 0; i < sizeof(watchpoints) / sizeof(*watchpoints); i++)
        {
            struct watchpoint* w = &watchpoints[i];
            if (w->enabled && (ram[w->address] != w->value))
            {
                printf("\nWatchpoint hit: %04x has changed from %02x to %02x\n",
                    w->address,
                    w->value,
                    ram[w->address]);
                w->value = ram[w->address];
                singlestepping = true;
            }
        }

        if (singlestepping)
            debug();
        else if (tracing)
            showregs();

        switch (pc)
        {
            case BDOS_ADDRESS:
                if (bdosbreak)
                    singlestepping = true;
                bdos_entry(cpu->registers->y, bdoslog);
                rts();
                continue;

            case BIOS_ADDRESS:
                if (bdosbreak)
                    singlestepping = true;
                bios_entry(cpu->registers->y);
                rts();
                continue;

            case EXIT_ADDRESS:
                exit(0);
        }

        if (ram[pc] == 0)
            cpu->registers->pc++;
        else
            M6502_run(cpu);
    }
}
