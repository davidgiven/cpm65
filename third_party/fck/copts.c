/*
 *	Small peephole optimizer. Tweaked and ANSIfied from
 *
 * DDS MICRO-C Optimizer
 *
 * This post-processor optimizes by reading the assembly source
 * code produced by the compiler, and recognizing specific instruction
 * sequences which it replaces with more efficient ones. It is entirely
 * table driven, making it fairly easy to port to any processor.
 *
 * ?COPY.TXT 1989-2005 Dave Dunfield
 *
 * The files contained is this archive are hereby released for anyone to use
 * for any reasonable purpose.
 *
 * If used for any reason resulting in published material, I request that you:
 * - Acknowlege the original author (Dave Dunfield)
 * - I do NOT require that you release derived source code, but please do
 *  provide information on where this original material may be obtained:
 *    https://dunfield.themindfactory.com
 *   "Daves Old Computers"
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>

extern const char *peep_table[];  /* Processor specific optimization table */

/* Values all chosen so they multiply easily by addition.. */

#define	PEEP_SIZE	16		/* size of peephole buffer must be power of 2 */
#define PEEP_MASK	(PEEP_SIZE - 1)
#define	LINE_SIZE	128		/* maximum size of input line */
#define SYMBOL_SIZE	48		/* maximum size of symbol */
#define SYMBOLS		8		/* maximum # symbols per peep */
/* Bit defintions in "special" table characters */
#define	SYMMASK		007		/* Mask for symbol number */
#define	SYMNUM		030		/* Symbol must be numeric */
#define	SYMNOT		040		/* Complement symbol */

/* circular peep hole buffer & read/write pointers */
static char peep_buffer[PEEP_SIZE][LINE_SIZE];
static unsigned peep_read;
static unsigned peep_write;

/* Symbol table */
static char symbols[SYMBOLS][SYMBOL_SIZE];
static char sym_used[SYMBOLS];

/* misc variables */
static char debug;

/*
 * Read a line into the peephole buffer from the input file.
 */
static unsigned read_line(void)
{
	if(fgets(peep_buffer[peep_write], LINE_SIZE, stdin)) {
		peep_write = (peep_write + 1) & PEEP_MASK;
		return 1; }
	return 0;
}

/*
 * Write a line from the peephole buffer to the output file.
 */
static void write_line(void)
{
	puts(peep_buffer[peep_read]);
	peep_read = (peep_read + 1) & PEEP_MASK;
}

/*
 * Compare an optimization table entry with a series of
 * instructions in the peephole buffer.
 * Return:	0	= No match
 *			-1	= Partial match
 *			n	= Full match ending at entry 'n'
 */
static int compare(char *ptr, unsigned peep)
{
	unsigned i, j;
	register char *ptr1, *ptr2, *ptr3;
	register char c, d;
#ifdef	LIMIT1
	unsigned x;
#endif

	for(i=0; i < SYMBOLS; ++i)
		sym_used[i] = 0;

	ptr1 = peep_buffer[peep];
	while((c = *ptr) != 0) {
		if(c == '\n') {				/* end of line */
			if(*ptr1)
				return 0;
			if((peep = (peep + 1) & PEEP_MASK) == peep_write)
				return -1;
			ptr1 = peep_buffer[peep];
		} else if(c == ' ' || c == '\t') {	/* spaces */
			if(!isspace(*ptr1))
				return 0;
			while(isspace(*ptr1))
				++ptr1;
		}
		else if (c & 0x80) {			/* symbol name */
			ptr2 = ptr3 = symbols[i = c & SYMMASK];
			d = *(ptr + 1);			/* Get terminator character */
			if(sym_used[i]) {		/* Symbol is already defined */
				while(*ptr1 && (*ptr1 != d))
					if(*ptr1++ != *ptr2++)
						return 0;
				if(*ptr2)
					return 0;
			} else {					/* new symbol definition */
				while(*ptr1 && (*ptr1 != d))
					*ptr2++ = *ptr1++;
				*ptr2 = 0;
				if(c & SYMNUM) {		/* Numbers only */
					while(*ptr3)
						if(!isdigit(*ptr3++))
							return 0;
#ifdef LIMIT1
					x = atoi(symbols[i]);
					switch(c & SYMNUM) {
						case 020: if(x > LIMIT1) return 0; break;
						case 030: if(x > LIMIT2) return 0; }
#endif
				}
				if(c & SYMNOT) {		/* Must be a NOT symbol */
					j = 0;
					do {
						if(!(ptr2 = not_table[j++]))
							return 0;
					}
					while(strcmp(ptr2, ptr3));
				}
				sym_used[i] = -1;
			}
		} else if(c != *ptr1++)		/* normal character */
			return 0;
		++ptr;
	}
	return (*ptr1) ? 0 : peep + 1;
}

/*
 * Exchange new code for old code in the peephole buffer.
 */
static void exchange(unsigned old, char *ptr)
{
	int i, j;
	register char *ptr1, *ptr2, c;

	/* if debugging, display instruction removed by optimizer */
	if(debug) {
		j = old & PEEP_MASK;
		for(i=peep_read; i != j; i = (i+1) & PEEP_MASK)
			fprintf(stdout,"Take: %s\n", peep_buffer[i]); }

	ptr2 = peep_buffer[peep_read = (old + PEEP_MASK) & PEEP_MASK];
	while((c = *ptr++) != 0) {
		if(c & 0x80) {
			ptr1 = symbols[c & SYMMASK];
			if(c & SYMNOT) {	 		/* Notted symbol */
				for(i=0; not_table[i]; ++i)
					if (!strcmp(ptr1, not_table[i])) {
						ptr1 = not_table[i ^ 0x01];
						break;
					}
				}
			while(*ptr1)
				*ptr2++ = *ptr1++;
		} else if(c == '\n') {
			*ptr2 = 0;
			ptr2 = peep_buffer[peep_read = (peep_read + (PEEP_SIZE-1)) % PEEP_SIZE];
		} else
			*ptr2++ = c;
	}
	*ptr2 = 0;

	/* if debugging, display instruction given by the optimizer */
	if(debug) {
		for(i=peep_read; i != j; i = (i+1) & PEEP_MASK)
			fprintf(stdout,"Give: %s\n", peep_buffer[i]);
	}
}

/*
 * Main program, read & optimize assembler source
 */

void usage(void)
{
	fputs("copt [-d] <input >output\n", stderr);
	exit(1);
}

int main(int argc, char *argv[])
{
	int i, j;
	register char *ptr;

	int opt;

	while ((opt = getopt(argc, argv, "d")) != -1) {
		if (opt == 'd')
			debug = 1;
		else
			usage();
	}
	if (optind <= argc)
		usage();		

	for(;;) {
		if((peep_read == peep_write) || (j == -1)) {
			if(!read_line()) {		/* End of file */
				while(peep_read != peep_write)
					write_line();
				exit(0);
			}
		}
		for(i = 0; (ptr = peep_table[i]) != 0; i += 2) {
			if((j = compare(ptr, peep_read)) != 0) {	/* we have a match */
				if(j == -1)						/* partial, wait */
					break;
				exchange(j, peep_table[i+1]);
				break;
			}
		}
		if(!ptr)			/* no matches, flush this line */
			write_line();
	}
}
