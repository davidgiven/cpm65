/*
 *	It's easiest to think of what cc does as a sequence of four
 *	conversions. Each conversion produces the inputs to the next step
 *	and the number of types is reduced. If the step is the final
 *	step for the conversion then the file is generated with the expected
 *	name but if it will be consumed by a later stage it is a temporary
 *	scratch file.
 *
 *	Stage 1: (-c -o overrides object name)
 *
 *	Ending			Action
 *	$1.S			preprocessor - may make $1.s
 *	$1.s			nothing
 *	$1.c			preprocessor, no-op or /dev/tty
 *	$1.o			nothing
 *	$1.a			nothing (library)
 *
 *	Stage 2: (not -E)
 *
 *	Ending			Action
 *	$1.s			nothing
 *	$1.%			cc, opt - make $1.s
 *	$1.o			nothing
 *	$1.a			nothing (library)
 *
 *	Stage 3: (not -E or -S)
 *
 *	Ending			Action
 *	$1.s			assembler - makes $1.o
 *	$1.o			nothing
 *	$1.a			nothing (library)
 *
 *	Stage 4: (run if no -c -E -S)
 *
 *	ld [each .o|.a in order] [each -l lib in order] -lc
 *	(with -b -o $1 etc)
 *
 *	TODO:
 *
 *	Platform specifics
 *	Search library paths for libraries (or pass to ld and make ld do it)
 *	Turn on temp removal once confident
 *	Split I/D
 */

#define DEBUG

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

/*
 *	For all non native compilers the directories moved and the rules
 *	are
 *
 *	BINPATH
 *		as
 *		cc		(this)
 *		ld		(try and share)
 *		reloc		(try and share)
 *
 *	LIBPATH
 *		cpp		(shared by all)
 *		cc0		(possibly shared may need work)
 *		cc1.cpuid
 *		cc2.cpuid
 *		copt		(shared by all)
 *		copt.cpuname
 *		cpuname/lib/
 *		cpuname/include/
 *		
 *	For the native compiler it gets built single CPU supporting
 *	as /bin/ccc /lib/cpp /lib/lib*.a /usr/include etc, but other processors
 *	are scanned in the usual rule.
 *
 *	Naming is two part
 *		cpuid		general naming for arch (eg 85, z80)
 *		cpuname		mach specific (z80,z180,8080,8085)
 */

#ifndef BINPATH
#define BINPATH		"/opt/fcc/bin/"
#define LIBPATH		"/opt/fcc/lib/"
#endif

struct obj {
	struct obj *next;
	char *name;
	uint8_t type;
#define TYPE_S			1
#define TYPE_C			2
#define TYPE_s			3
#define TYPE_C_pp		4
#define TYPE_O			5
#define TYPE_A			6
	uint8_t used;
};

struct objhead {
	struct obj *head;
	struct obj *tail;
};

struct objhead objlist;
struct objhead liblist;
struct objhead inclist;
struct objhead deflist;
struct objhead libpathlist;
struct objhead ccargs;		/* Arguments to pass on to the compiler */

struct cpu_table {
	const char *name;	/* Name to match */
	const char *set;	/* Binary names in bin */
	const char *cpudot;	/* .xxxx name for lib helpers */
	const char *lib;	/* System library path naming */
	const char *cpudir;	/* Directory for this CPU include etc (some may share) */
	const char **defines;	/* CPU defines */
	const char **ldopts;	/* LD link rules */
	const char *cpucode;	/* CPU code value for backend */
	unsigned has_reloc;	/* Has relocatable binary support */
	const char **cpufeat;	/* Feature option names in bit flag order */
};

const char *def6502[] = { "__6502__", NULL };
const char *def65c02[] = { "__6502__", "__65c02__", NULL };
const char *def65c816[] = { "__65c816__", NULL };
const char *def6303[] = { "__6803__", "__6303__", NULL };
const char *def6800[] = { "__6800__", "__6800__", NULL };
const char *def6803[] = { "__6803__", NULL };
const char *def68hc11[] = { "__68hc11__", "__6803__", NULL };
const char *def6809[] = { "__6809__", NULL };
const char *def8080[] = { "__8080__", NULL };
const char *def8085[] = { "__8085__", NULL };
const char *defz80[] = { "__z80__", NULL };
const char *z80feat[] = {
	"banked",
	"noix",
	"noiy",
	NULL
};

const char *defz180[] = { "__z80__", "__z180__", NULL };
const char *defbyte[] = { "__byte__", NULL };
const char *defthread[] = { "__thread__", NULL };
const char *defz8[] = { "__z8__", NULL };
const char *defsuper8[] = { "__super8__", NULL };
const char *def1802[] = { "__1802__", NULL };
const char *def1805[] = { "__1805__", NULL };
const char *def8070[] = { "__8070__", NULL };
const char *def8086[] = { "__8086__", NULL };
const char *def80186[] = { "__8086__", "__80186__", NULL };
const char *defee200[] = { "__ee200__", "__cpu4__", NULL };
const char *defnova[] = { "__nova__", NULL };
const char *defnova3[] = { "__nova3__", "__nova__", NULL };
const char *novafeat[] = {
	"multiply",
	NULL
};

const char *ld6502[] = { "-b", "-C", "512", "-Z", "0x00", NULL };
const char *ld6800[] = { "-b", "-C", "256", "-Z", "0x40", NULL };
const char *ld6809[] = { "-b", "-C", "256", NULL };
const char *ld8070[] = { "-b", "-C", "1", NULL };
const char *ld8080[] = { "-b", "-C", "256", NULL };
const char *ld8086[] = { "-b", "-C", "256", NULL };
const char *ldee200[] = { "-b", "-C", "256", NULL };
const char *ldnova[] = { "-b", "-Z", "050", "-C", "512", NULL };
const char *ldbyte[] =  { NULL };
const char *ldthread[] = { NULL };
const char *cpucode;

struct cpu_table cpu_rules[] = {
	{ "6502", "6502", ".6502", "lib6502.a", "6502", def6502, ld6502, "0", 0, NULL },
	{ "65c02", "6502", ".6502", "lib65c02.a", "65c02", def65c02, ld6502, "1" , 0, NULL},
	{ "65c816", "6502", ".65c816", "lib65c816.a", "65c816", def65c816, ld6502, "0" , 0, NULL},
	{ "6303", "6800", ".6800", "lib6303.a", "6303", def6303, ld6800, "6303" , 1, NULL},
	{ "6800", "6800", ".6800", "lib6800.a", "6800", def6800, ld6800, "6800" , 1, NULL},
	{ "6803", "6800", ".6800", "lib6803.a", "6803", def6803, ld6800, "6803" , 1, NULL},
	/* Until we do 6309 specifics */
	{ "6309", "6809", ".6809", "lib6809.a", "6809", def6809, ld6809, "6809" , 1, NULL},
	{ "6809", "6809", ".6809", "lib6809.a", "6809", def6809, ld6809, "6809" , 1, NULL},
	{ "68hc11", "hc11", ".6800", "lib68hc11.a", "68hc11", def68hc11, ld6800, "6811" , 1, NULL},
	{ "8080", "8080", ".8080", "lib8080.a", "8080", def8080, ld8080, "8080" , 0, NULL},
	{ "8085", "8080", ".8080", "lib8085.a", "8085", def8085, ld8080, "8085" , 0, NULL},
	{ "z80", "z80", ".z80", "libz80.a", "z80", defz80, ld8080, "80" , 1, z80feat},
	{ "z180", "z80", ".z80", "libz180.a", "z80", defz180, ld8080, "180" , 1, z80feat},
	/* Other Z80 variants TODO */
	/* Similar issues. We may end up making this a bunch of CPU specifics
	   anyway because of endianness, alignment etc */
	{ "thread", "thread", ".thread", "libthread.a", "thread", defthread, ldbyte, "0", 0, NULL },
	{ "z8", "z8", ".z8", "libz8.a", "z8", defz8, ld8080, "8" , 0, NULL},
	{ "super8", "super8", ".super8", "libsuper8.a", "super8", defsuper8, ld8080, "8" , 0, NULL},
	{ "1802", "1802", ".1802", "lib1802.a", "1802", def1802, ld8080, "2" , 0, NULL},
	{ "1805", "1802", ".1802", "lib1805.a", "1802", def1805, ld8080, "5" , 0, NULL},
	{ "8070", "8070", ".8070", "lib8070.a", "8070", def8070, ld8070, "8070" , 0, NULL},
	{ "8086", "8086", ".8086", "lib8086.a", "8086", def8086, ld8086, "86" , 0, NULL},
	{ "80186", "8086", ".8086", "lib80186.a", "80186", def80186, ld8086, "186" , 0, NULL},
	{ "ee200", "ee200", ".ee200", "libee200.a", "ee200", defee200, ldee200, "4", 0, NULL },
	/* For now we are not doing anything with the CPU features on later processors */
	{ "wrx5", "ee200", ".ee200", "libee200.a", "ee200", defee200, ldee200, "5", 0, NULL },
	{ "wrx6", "ee200", ".ee200", "libee200.a", "ee200", defee200, ldee200, "6", 0, NULL },
	/* Nova with autoinc/dec but not necessarily stack */
	{ "nova", "nova", ".nova", "libnova.a", "nova", defnova, ldnova, "0", 0, novafeat },
	/* Nova with stack hardware (3+) */
	{ "nova3", "nova", ".nova", "libnova3.a", "nova", defnova3, ldnova, "3", 0, novafeat },
	{ NULL }
};

/* Need to set these via the cpu type lookup etc */
int native;
const char *cpuset;		/* Which binary compiler tool names */
const char *cpudot;		/* Which internal tool names */
const char *cpudir;		/* CPU specific directory */
const char *cpulib;		/* Dir for this compiler */
const char **cpudef;		/* List of defines */
const char **ldopts;		/* Linker opts for default link */
unsigned has_relocs;		/* Do we have relocations ? */
const char **feats;		/* CPU features */
unsigned long features;		/* Bit mask of feature info for pass 2 */

/* We will need to do more with ldopts for different OS and machine targets
   eventually */

const char *crtname = "crt0.o";

int print_passes=0;
int keep_temp;
int last_phase = 4;
int only_one_input;
char *target;
int strip;
int c_files;
int standalone;
char *cpu = "8080";
int mapfile;

#define OS_NONE		0
#define OS_FUZIX	1
int targetos = OS_FUZIX;
int fuzixsub;
char optimize = '0';
char *codeseg;

char *symtab;

#define MAXARG	512

int arginfd, argoutfd;
const char *arglist[MAXARG];
const char **argptr;
char *rmlist[MAXARG];
char **rmptr = rmlist;

static void remove_temporaries(void)
{
	char **p = rmlist;
	while (p < rmptr) {
		if (keep_temp == 0)
			unlink(*p);
		free(*p++);
	}
	rmptr = rmlist;
}

static void fatal(void)
{
	remove_temporaries();
	if (symtab && keep_temp == 0)
		unlink(symtab);
	exit(1);
}

static void memory(void)
{
	fprintf(stderr, "cc: out of memory.\n");
	fatal();
}

static char *xstrdup(char *p, int extra)
{
	char *n = malloc(strlen(p) + extra + 1);
	if (n == NULL)
		memory();
	strcpy(n, p);
	return n;
}

#define CPATHSIZE	256

static char pathbuf[CPATHSIZE];

/* Binaries. Native ones in /bin, non-native ones in
   <bindir>/app{.cpu} */
static char *make_bin_name(const char *app, const char *t)
{
	/* TODO use strlcpy/cat */
	if (native)
		snprintf(pathbuf, CPATHSIZE, "/bin/%s", app);
	else
		snprintf(pathbuf, CPATHSIZE, "%s/%s%s", BINPATH, app, t);
	return pathbuf;
}

/* Library area. Native ones in /lib, non-native ones in
   <libdir>/app{.cpu} */
static char *make_lib_name(const char *app, const char *tail)
{
	if (native)
		snprintf(pathbuf, CPATHSIZE, "/lib/%s", app);
	else
		snprintf(pathbuf, CPATHSIZE, "%s/%s%s", LIBPATH, app, tail);
	return pathbuf;
}

/* The library area for a target. For native this is /lib and /usr/include but
   for non-native we use <libdir>/<cpu>/{include, lib, ..} */
static char *make_lib_dir(const char *base, const char *tail)
{
	if (native)
		snprintf(pathbuf, CPATHSIZE, "%s/%s", base, tail);
	else
		snprintf(pathbuf, CPATHSIZE, "%s/%s/%s", LIBPATH, cpudir, tail);
	return pathbuf;
}

static char *make_lib_file(const char *base, const char *dir, const char *tail)
{
	if (native)
		snprintf(pathbuf, CPATHSIZE, "%s/%s/%s", base, dir, tail);
	else
		snprintf(pathbuf, CPATHSIZE, "%s/%s/%s", LIBPATH, cpudir, tail);
	return pathbuf;
}

/*
 *	Work out what we actually need to run
 */

static void set_for_processor(struct cpu_table *r)
{
	cpuset = r->set;
	cpudot = r->cpudot;
	cpudir = r->cpudir;
	cpulib = r->lib;	
	cpudef = r->defines;
	ldopts = r->ldopts;
	cpucode = r->cpucode;
	has_relocs = r->has_reloc;
	feats = r->cpufeat;
}

static void find_processor(const char *cpu)
{
	struct cpu_table *t = cpu_rules;
#ifdef NATIVE_CPU
	if (strcmp(cpu, NATIVE_CPU) == 0)
		native = 1;
#endif
	while(t->name) {
		if (strcmp(t->name, cpu) == 0) {
			set_for_processor(t);
			return;
		}
		t++;
	}
	fprintf(stderr, "cc: unknown CPU type '%s'.\n", cpu);
	exit(1);
}

static void append_obj(struct objhead *h, char *p, uint8_t type)
{
	struct obj *o = malloc(sizeof(struct obj));
	if (o == NULL)
		memory();
	o->name = p;
	o->next = NULL;
	o->used = 0;
	o->type = type;
	if (h->tail)
		h->tail->next = o;
	else
		h->head = o;
	h->tail = o;
}

/* Modify the filename p in-place, losing the f suffix
   and applying the t suffix. Return a copy of the p pointer.
   Add the filename to the list of files to remove if rmif
   is earlier than the last phase.

   However, if this_phase matches last_phase,
   simply return the target filename if it exists. */
static char *pathmod(char *p, char *f, char *t, int rmif, int this_phase)
{
	char *x;

	if (this_phase == last_phase && target != NULL)
		return(target);
	x = strrchr(p, '.');
	if (x == NULL) {
		fprintf(stderr, "cc: no extension on '%s'.\n", p);
		fatal();
	}
#if 0
	if (strcmp(x, f)) {
		fprintf(stderr, "cc: internal got '%s' expected '%s'.\n",
			p, t);
		fatal();
	}
#endif
	strcpy(x, t);
	if (last_phase > rmif) {
		*rmptr++ = xstrdup(p, 0);
	}
	return p;
}

static void add_argument(const char *p)
{
	if (argptr == &arglist[MAXARG]) {
		fprintf(stderr, "cc: too many arguments to command.\n");
		fatal();
	}
	*argptr++ = p;
}

static void add_argument_list(char *header, struct objhead *h)
{
	struct obj *i = h->head;
	while (i) {
		if (header)
			add_argument(header);
		add_argument(i->name);
		i->used = 1;
		i = i->next;
	}
}

static char *resolve_library(char *p)
{
	static char buf[512];
	struct obj *o = libpathlist.head;
	if (strchr(p, '/') || strchr(p, '.'))
		return p;
	while(o) {
		snprintf(buf, 512, "%s/lib%s.a", o->name, p);
		if (access(buf, 0) == 0)
			return xstrdup(buf, 0);
		o = o->next;
	}
	return NULL;
}

/* This turns -L/opt/foo/lib  -lfoo -lbar into resolved names like
   /opt/foo/lib/libfoo.a */
static void resolve_libraries(void)
{
	struct obj *o = liblist.head;
	while(o != NULL) {
		char *p = resolve_library(o->name);
		if (p == NULL) {
			fprintf(stderr, "cc: unable to find library '%s'.\n", o->name);
			fatal();
		}
		add_argument(p);
		o = o->next;
	}
}

static void run_command(void)
{
	pid_t pid, p;
	const char **ptr;
	int status;

	fflush(stdout);

	*argptr = NULL;

	pid = fork();
	if (pid == -1) {
		perror("fork");
		fatal();
	}
	if (pid == 0) {
#ifdef DEBUG
		if (print_passes) {
			ptr = arglist;
			printf("[");
			while(*ptr)
				printf("%s ", *ptr++);
			printf("]\n");
		}
#endif
		fflush(stdout);
		if (arginfd != -1) {
			dup2(arginfd, 0);
			close(arginfd);
		}
		if (argoutfd != -1) {
			dup2(argoutfd, 1);
			close(argoutfd);
		}
		execv(arglist[0], (char **)arglist);
		perror(arglist[0]);
		exit(255);
	}
	if (arginfd)
		close(arginfd);
	if (argoutfd)
		close(argoutfd);
	while ((p = waitpid(pid, &status, 0)) != pid) {
		if (p == -1) {
			perror("waitpid");
			fatal();
		}
	}
	if (WIFSIGNALED(status)) {
		/* Scream loudly if it exploded */
		fprintf(stderr, "cc: %s failed with signal %d.\n", arglist[0],
			WTERMSIG(status));
		fatal();
	}
	/* Quietly exit if the stage errors. That means it has reported
	   things to the user */
	if (WEXITSTATUS(status))
		fatal();
}

static void redirect_in(const char *p)
{
	arginfd = open(p, O_RDONLY);
	if (arginfd == -1) {
		perror(p);
		fatal();
	}
#ifdef DEBUG
	if (print_passes)
		printf("<%s\n", p);
#endif
}

static void redirect_out(const char *p)
{
	argoutfd = open(p, O_RDWR | O_CREAT | O_TRUNC, 0666);
	if (argoutfd == -1) {
		perror(p);
		fatal();
	}
#ifdef DEBUG
	if (print_passes)
		printf(">%s\n", p);
#endif
}

static void build_arglist(char *p)
{
	arginfd = -1;
	argoutfd = -1;
	argptr = arglist;
	add_argument(p);
}


void convert_s_to_o(char *path)
{
	char *origpath= strdup(path);
	build_arglist(make_bin_name("as", cpuset));
	add_argument("-o");
	add_argument(pathmod(path, ".s", ".o", 5, 3));
	add_argument(origpath);
	run_command();
	free(origpath);
}

void convert_c_to_s(char *path)
{
	char *tmp, *t, *p;
	char optstr[2];
	char featstr[16];

	snprintf(featstr, 16, "%lu", features);

	build_arglist(make_lib_name("cc0", ""));
	add_argument(symtab);
	t = xstrdup(path, 0);
	tmp = pathmod(t, ".c", ".%", 0, 255);
	redirect_in(tmp);
	t = xstrdup(path, 0);
	tmp = pathmod(t, ".%", ".@", 0, 255);
	if (tmp == NULL)
		memory();
	redirect_out(tmp);
	run_command();

	build_arglist(make_lib_name("cc1", cpudot));
	add_argument(cpucode);
	add_argument(featstr);
	redirect_in(tmp);
	tmp = pathmod(path, ".@", ".#", 0, 255);
	redirect_out(tmp);
	run_command();

	build_arglist(make_lib_name("cc2", cpudot));
	add_argument(symtab);
	add_argument(cpucode);
	/* FIXME: need to change backend.c parsing for above and also
	   add another arg when we do the new subcpu bits like -banked */
	optstr[0] = optimize;
	optstr[1] = '\0';
	add_argument(optstr);
	add_argument(featstr);
	if (codeseg)
		add_argument(codeseg);
	redirect_in(tmp);
	if (optimize == '0') {
		redirect_out(pathmod(path, ".#", ".s", 2, 2));
		run_command();
		free(t);
		return;
	}
	tmp = pathmod(path, ".#", ".^", 0, 255);
	redirect_out(tmp);
	run_command();

	/* TODO: with the new copt we may end up with a copt per cpu */
	p = xstrdup(make_lib_name("copt", ""), 0);
	build_arglist(p);
	add_argument(make_lib_name("rules.", cpuset));
	redirect_in(tmp);
	redirect_out(pathmod(path, ".#", ".s", 2, 2));
	run_command();
	free(t);
	free(p);
}

void convert_S_to_s(char *path)
{
	char *tmp;
	build_arglist(make_lib_name("cpp", ""));
	add_argument("-E");
	add_argument(path);
	tmp = xstrdup(path, 0);
	redirect_out(pathmod(tmp, ".S", ".s", 1, 2));
	run_command();
	pathmod(path, ".S", ".s", 5, 2);
}

void preprocess_c(char *path)
{
	char *tmp;

	build_arglist(make_lib_name("cpp", ""));

	add_argument_list("-I", &inclist);
	add_argument_list("-D", &deflist);
	add_argument("-E");
	add_argument(path);
	/* Weird one .. -E goes to stdout */
	tmp = xstrdup(path, 0);
	if (last_phase != 1)
		redirect_out(pathmod(tmp, ".c", ".%", 0, 1));
	run_command();
}

void link_phase(void)
{
	char *relocs = NULL;
	char *p, *l, *c;
	/* TODO: ld should be general if we get it right, but might not be able to */
	p = xstrdup(make_bin_name("ld", cpuset), 0);

	/* Set the target as a.out if there is no target */
	if (target==NULL)
		target= "a.out";

	build_arglist(p);
	switch (targetos) {
		case OS_FUZIX:
			switch(fuzixsub) {
			case 0:
/* FIXME: Needs to move to a per target flag set, as do the various other
   option defaults (eg -C 256 makes no sense for 6502 */
				if (has_relocs) {
					relocs = xstrdup(target, 4);
					strcat(relocs, ".rel");
				}
				break;
			case 1:
				add_argument("-b");
				add_argument("-C");
				add_argument("256");
				break;
			case 2:
				add_argument("-b");
				add_argument("-C");
				add_argument("512");
				break;
			}
			break;
		case OS_NONE:
		default: {
				const char **x = ldopts;
				while(*x) {
					add_argument(*x);
					x++;
				}
			}
			break;
	}
	if (strip)
		add_argument("-s");
	add_argument("-o");
	add_argument(target);
	if (mapfile) {
		/* For now output a map file. One day we'll have debug symbols
		   nailed to the binary */
		char *n = xstrdup(target, 4);
		strcat(n, ".map");
		add_argument("-m");
		add_argument(n);
	}
	if (relocs) {
		add_argument("-R");
		add_argument(relocs);
	}
	/* <root>/8080/lib/ */
	l = xstrdup(make_lib_dir("", ""), 0);
	c = NULL;
	if (!standalone) {
		/* Start with crt0.o, end with libc.a and support libraries */
		c = xstrdup(make_lib_file("", "lib", crtname), 0);
		add_argument(c);
		append_obj(&libpathlist, l, 0);
		append_obj(&libpathlist, ".", 0);
		append_obj(&liblist, "c", TYPE_A);
	}
	/* Will be <root>/8080/lib/lib8080.a etc */
	append_obj(&liblist, make_lib_file("", "lib", cpulib), TYPE_A);
	add_argument_list(NULL, &objlist);
	resolve_libraries();
	run_command();

	free(c);
	free(l);
	free(p);

	if (relocs) {
		/* The unlink will free it not us */
		*rmptr++ = relocs;
		build_arglist(make_bin_name("reloc", cpuset));
		add_argument(target);
		add_argument(relocs);
		run_command();
	}
}

void sequence(struct obj *i)
{
/*	printf("Last Phase %d\n", last_phase); */
/*	printf("1:Processing %s %d\n", i->name, i->type); */
	if (i->type == TYPE_S) {
		convert_S_to_s(i->name);
		i->type = TYPE_s;
		i->used = 1;
	}
	if (i->type == TYPE_C) {
		preprocess_c(i->name);
		i->type = TYPE_C_pp;
		i->used = 1;
	}
	if (last_phase == 1)
		return;
/*	printf("2:Processing %s %d\n", i->name, i->type); */
	if (i->type == TYPE_C_pp || i->type == TYPE_C) {
		convert_c_to_s(i->name);
		i->type = TYPE_s;
		i->used = 1;
	}
	if (last_phase == 2)
		return;
/*	printf("3:Processing %s %d\n", i->name, i->type); */
	if (i->type == TYPE_s) {
		convert_s_to_o(i->name);
		i->type = TYPE_O;
		i->used = 1;
	}
}

void processing_loop(void)
{
	struct obj *i = objlist.head;
	while (i) {
		sequence(i);
		remove_temporaries();
		i = i->next;
	}
	if (last_phase < 4)
		return;
	link_phase();
	/* And clean up anything we couldn't wipe earlier */
	last_phase = 255;
	remove_temporaries();
}

void unused_files(void)
{
	struct obj *i = objlist.head;
	while (i) {
		if (!i->used)
			fprintf(stderr, "cc: warning file %s unused.\n",
				i->name);
		i = i->next;
	}
}

void usage(void)
{
	FILE *f = fopen(make_lib_name("cc.hlp", ""), "r");
	if (f == NULL)
		perror("cc.hlp");
	else {
		while(fgets(pathbuf, CPATHSIZE, f))
			fputs(pathbuf, stdout);
	}
	fatal();
}

char **add_macro(char **p)
{
	if ((*p)[2])
		append_obj(&deflist, *p + 2, 0);
	else
		append_obj(&deflist, *++p, 0);
	return p;
}

char **add_library(char **p)
{
	if ((*p)[2])
		append_obj(&liblist, *p + 2, TYPE_A);
	else
		append_obj(&liblist, *++p, TYPE_A);
	return p;
}

char **add_library_path(char **p)
{
	if ((*p)[2])
		append_obj(&libpathlist, *p + 2, 0);
	else
		append_obj(&libpathlist, *++p, 0);
	return p;
}


char **add_includes(char **p)
{
	if ((*p)[2])
		append_obj(&inclist, *p + 2, 0);
	else
		append_obj(&inclist, *++p, 0);
	return p;
}

void add_system_include(void)
{
	append_obj(&inclist, xstrdup(make_lib_dir("usr", "include"), 0), 0);
}

void dunno(const char *p)
{
	fprintf(stderr, "cc: don't know what to do with '%s'.\n", p);
	fatal();
}

void add_file(char *p)
{
	char *x = strrchr(p, '.');
	if (x == NULL)
		dunno(p);
	switch (x[1]) {
	case 'a':
		append_obj(&objlist, p, TYPE_A);
		break;
	case 's':
		append_obj(&objlist, p, TYPE_s);
		break;
	case 'S':
		append_obj(&objlist, p, TYPE_S);
		break;
	case 'c':
		append_obj(&objlist, p, TYPE_C);
		c_files++;
		break;
	case 'o':
		append_obj(&objlist, p, TYPE_O);
		break;
	default:
		dunno(p);
	}
}

void one_input(void)
{
	fprintf(stderr, "cc: too many files for -E\n");
	fatal();
}

void uniopt(char *p)
{
	if (p[2])
		usage();
}

void extended_opt(const char *p)
{
	if (strcmp(p, "dlib") == 0) {
		crtname = "lib0.o";
		return;
	}
	usage();
}

void find_opt(const char *p)
{
	const char **op = feats;
	unsigned n = 1;
	if (op) {
		while(*op) {
			if (strcmp(p, *op) == 0) {
				features |= n;
				return;
			}
			op++;
			n *= 2;
		}
	}
	usage();
}
		
int main(int argc, char *argv[]) {
	char **p = argv;
	unsigned c;
	char *o;
	char o2;

	signal(SIGCHLD, SIG_DFL);

	while (*++p) {
		/* filename or option ? */
		if (**p != '-') {
			add_file(*p);
			continue;
		}
		c = (*p)[1];
		if (c == '-') {
			extended_opt(*p + 2);
			continue;
		}
		switch (c) {
			/* Extended options (for now never with args) */
			/* Don't link */
		case 'c':
			uniopt(*p);
			last_phase = 3;
			break;
			/* Don't assemble */
		case 'S':
			uniopt(*p);
			last_phase = 2;
			break;
			/* Only pre-process */
		case 'E':
			uniopt(*p);
			last_phase = 1;
			only_one_input = 1;
			break;
		case 'l':
			p = add_library(p);
			break;
		case 'I':
			p = add_includes(p);
			break;
		case 'L':
			p = add_library_path(p);
			break;
		case 'D':
			p = add_macro(p);
			break;
		case 'i':
/*                    split_id();*/
			uniopt(*p);
			break;
		case 'o':
			if (target != NULL) {
				fprintf(stderr,
					"cc: -o can only be used once.\n");
				fatal();
			}
			if ((*p)[2])
				target = *p + 2;
			else if (*p)
				target = *++p;
			else {
				fprintf(stderr, "cc: no target given.\n");
				fatal();
			}
			break;
		case 'O':
			if ((*p)[2]) {
				o2 = (*p)[2];
				if (o2 >= '0' && o2 <= '3')
					optimize = o2;
				else if (o2 == 's')
					optimize = 's';
				else {
					fprintf(stderr, "cc: unknown optimisation level.\n");
					fatal();
				}
			} else
				optimize = '1';
			break;
		case 's':	/* FIXME: for now - switch to getopt */
			standalone = 1;
			break;
		case 'V':
			print_passes = 1;
			break;
		case 'X':
			uniopt(*p);
			keep_temp++;
			break;
		case 'm':
			cpu = *p + 2;
			break;	
		case 'M':
			mapfile = 1;
			break;
		case 't':
			if (strcmp(*p + 2, "none") == 0) {
				targetos = OS_NONE;
			} else if (strcmp(*p + 2, "fuzix") == 0) {
				targetos = OS_FUZIX;
				fuzixsub = 0;
			} else if (strcmp(*p + 2, "fuzixrel1") == 0) {
				targetos = OS_FUZIX;
				fuzixsub = 1;
			} else if (strcmp(*p + 2, "fuzixrel2") == 0) {
				targetos = OS_FUZIX;
				fuzixsub = 2;
			} else {
				fprintf(stderr, "cc: only fuzix target types are known.\n");
				fatal();
			}
			break;
		case 'T':
			codeseg = *p + 2;
			break;
		default:
			usage();
		}
	}

	o = strchr(cpu, '-');
	if (o)
		*o++ = 0;
	find_processor(cpu);
	if (o) {
		o = strtok(o, "-");
		while(o) {
			find_opt(o);
			o = strtok(NULL, "-");
		}
	}

	while(*cpudef)
		append_obj(&deflist, (char *)*cpudef++, 0);

	if (!standalone)
		add_system_include();

	if (only_one_input && c_files > 1)
		one_input();

	symtab = xstrdup(".symtmp", 6);
	snprintf(symtab + 7, 6, "%x", getpid());
	processing_loop();
	unused_files();
	if (keep_temp < 2)
		unlink(symtab);
	return 0;
}
