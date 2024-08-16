/*
 *	This is the main block for the code generator. It provides the
 *	basic parsing functions to make life easy for the target code
 *	generator. A target is not required to use this, it can work the
 *	tree/header mix any way it wants.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>

#include "symtab.h"
#include "compiler.h"
#include "backend.h"

int sym_fd = -1;

unsigned cpu;
unsigned opt;
unsigned optsize;
unsigned long cpufeat;
const char *codeseg = "code";

static unsigned process_one_block(uint8_t * h);

static const char *argv0;

void error(const char *p)
{
	fprintf(stderr, "%s: error: %s\n", argv0, p);
	exit(1);
}

static void xread(int fd, void *buf, int len)
{
	if (read(fd, buf, len) != len)
		error("short read");
}

/*
 *	Name symbol table.
 *
 *	We can just cache bits of this in cc2 if we actually get tight on
 *	space. It's not a big deal as we only use names for global and static
 *	objects.
 */

#define NCACHE_SIZE	32
static struct name names[NCACHE_SIZE];
static struct name *nhead;
static unsigned max_name;

char *namestr(register unsigned n)
{
	register struct name *np = nhead;
	register struct name *prev = NULL;
	while (np) {
		if (np->id == n) {
			if (prev) {
				prev->next = np->next;
				np->next = nhead;
				nhead = np;
			}
			return np->name;
		}
		prev = np;
		np = np->next;
	}
	/* Hack for now we need to pick a better node */
	if (lseek(sym_fd, 2 + sizeof(struct name) * (n & 0x7FFF), 0) < 0)
		error("seeksym");
	xread(sym_fd, prev, sizeof(struct name));
	prev->next = NULL;
	return prev->name;
}

static void init_name_cache(void)
{
	register unsigned i;
	register struct name *np = names;
	for (i = 0; i < NCACHE_SIZE - 1; i++) {
		np->next = np + 1;
		np++;
	}
	np->next = NULL;
	nhead = names;
}

/*
 *	Expression tree nodes
 */
#define NUM_NODES 100

static struct node node_table[NUM_NODES];
static struct node *nodes;

struct node *new_node(void)
{
	register struct node *n;
	if (nodes == NULL)
		error("Too many nodes");
	n = nodes;
	nodes = n->right;
	n->left = n->right = NULL;
	n->value = 0;
	n->flags = 0;
	return n;
}

void free_node(register struct node *n)
{
	n->right = nodes;
	nodes = n;
}

void init_nodes(void)
{
	register int i;
	register struct node *n = node_table;
	for (i = 0; i < NUM_NODES; i++)
		free_node(n++);
}

void free_tree(register struct node *n)
{
	if (n->left)
		free_tree(n->left);
	if (n->right)
		free_tree(n->right);
	free_node(n);
}

/* Small stack of segments so we can untangle literals etc */

static unsigned segs[MAX_SEG];
static unsigned *segp = segs;
static unsigned last_seg;

static void push_area(unsigned s)
{
	if (segp == &segs[MAX_SEG])
		error("pua");
	*segp++ = last_seg;
	if (last_seg != s) {
		gen_segment(s);
		last_seg = s;
	}
}

static void pop_area(void)
{
	if (segp == segs)
		error("poa");
	segp--;
	/* Last pop is to "nothing" so we don't need to act */
	if (segp > segs && last_seg != *segp) {
		gen_segment(*segp);
		last_seg = *segp;
	}
}

/* I/O buffering stuff can wait - as can switching to a block write method */
static struct node *load_tree(void)
{
	register struct node *n = new_node();
	xread(0, n, sizeof(struct node));

	/* The values off disk are old pointers or NULL, that's good enough
	   to use as a load flag */
	if (n->left)
		n->left = load_tree();
	if (n->right)
		n->right = load_tree();
	return n;
}

static unsigned depth = 0;

static struct node *rewrite_tree(register struct node *n)
{
	register unsigned f = 0;
	depth++;
/*	printf("; %-*s %04x (%ld)\n", depth, "", n->op, n->value); */
	if (n->left) {
		n->left = rewrite_tree(n->left);
		f |= n->left->flags;
	}
	if (n->right) {
		n->right = rewrite_tree(n->right);
		f |= n->right->flags;
	}
	if (f & (SIDEEFFECT | IMPURE))
		n->flags |= IMPURE;
	depth--;
	/* Convert LVAL flag into pointer type */
	if (n->flags & LVAL)
		n->type++;
	/* Turn any remaining object references (functions) into pointer type */
	/* Need to review how we do this with name of function versus function vars etc */
	/* FIXME */
	if (IS_FUNCTION(n->type))
		n->type = PTRTO;
	return gen_rewrite_node(n);
}

#ifdef DEBUG

/* Return the operation's name, or NULL */
static char *getopname(int op) {
	switch(op) {
		case 0x8000: return("T_SYMBOL");
		case 0x7F00: return("T_EOF");
		case 0x7F01: return("T_INVALID");
		case 0x7F02: return("T_POT");
		case 0x0110: return("T_SHLEQ");
		case 0x0111: return("T_SHREQ");
		case 0x0112: return("T_POINTSTO");
		case 0x0113: return("T_ELLIPSIS");
		case 0x0120: return("T_PLUSPLUS");
		case 0x0121: return("T_MINUSMINUS");
		case 0x0122: return("T_EQEQ");
		case 0x0123: return("T_LTLT");
		case 0x0124: return("T_GTGT");
		case 0x0125: return("T_OROR");
		case 0x0126: return("T_ANDAND");
		case 0x0201: return("T_MINUSEQ");
		case 0x0202: return("T_SLASHEQ");
		case 0x0203: return("T_STAREQ");
		case 0x0204: return("T_HATEQ");
		case 0x0205: return("T_BANGEQ");
		case 0x0206: return("T_OREQ");
		case 0x0207: return("T_ANDEQ");
		case 0x0208: return("T_PERCENTEQ");
		case 0x0209: return("T_LTEQ");
		case 0x020A: return("T_GTEQ");
		case 0x0200: return("T_PLUSEQ");
		case '(': return("T_LPAREN");
		case ')': return("T_RPAREN");
		case '[': return("T_LSQUARE");
		case ']': return("T_RSQUARE");
		case '{': return("T_LCURLY");
		case '}': return("T_RCURLY");
		case '&': return("T_AND");
		case '*': return("T_STAR");
		case '/': return("T_SLASH");
		case '%': return("T_PERCENT");
		case '+': return("T_PLUS");
		case '-': return("T_MINUS");
		case '?': return("T_QUESTION");
		case ':': return("T_COLON");
		case '^': return("T_HAT");
		case '<': return("T_LT");
		case '>': return("T_GT");
		case '|': return("T_OR");
		case '~': return("T_TILDE");
		case '!': return("T_BANG");
		case '=': return("T_EQ");
		case ';': return("T_SEMICOLON");
		case '.': return("T_DOT");
		case ',': return("T_COMMA");
		case 0x1000: return("T_CHAR");
		case 0x1001: return("T_DOUBLE");
		case 0x1002: return("T_ENUM");
		case 0x1003: return("T_FLOAT");
		case 0x1004: return("T_INT");
		case 0x1005: return("T_LONG");
		case 0x1006: return("T_SHORT");
		case 0x1007: return("T_SIGNED");
		case 0x1008: return("T_STRUCT");
		case 0x1009: return("T_UNION");
		case 0x100A: return("T_UNSIGNED");
		case 0x100B: return("T_VOID");
		case 0x100C: return("T_AUTO");
		case 0x100D: return("T_EXTERN");
		case 0x100E: return("T_REGISTER");
		case 0x100F: return("T_STATIC");
		case 0x1010: return("T_CONST");
		case 0x1011: return("T_VOLATILE");
		case 0x1012: return("T_BREAK");
		case 0x1013: return("T_CASE");
		case 0x1014: return("T_CONTINUE");
		case 0x1015: return("T_DEFAULT");
		case 0x1016: return("T_DO");
		case 0x1017: return("T_ELSE");
		case 0x1018: return("T_FOR");
		case 0x1019: return("T_GOTO");
		case 0x101A: return("T_IF");
		case 0x101B: return("T_RETURN");
		case 0x101C: return("T_SIZEOF");
		case 0x101D: return("T_SWITCH");
		case 0x101E: return("T_TYPEDEF");
		case 0x101F: return("T_WHILE");
		case 0x1020: return("T_RESTRICT");
		case 0x1100: return("T_INTVAL");
		case 0x1101: return("T_UINTVAL");
		case 0x1102: return("T_LONGVAL");
		case 0x1103: return("T_ULONGVAL");
		case 0x1104: return("T_FLOATVAL");
		case 0x1105: return("T_STRING");
		case 0x1106: return("T_STRING_END");
		case 0x1200: return("T_CAST");
		case 0x1201: return("T_CONSTANT");
		case 0x1202: return("T_NAME");
		case 0x1203: return("T_LOCAL");
		case 0x1204: return("T_LABEL");
		case 0x1205: return("T_ARGUMENT");
		case 0x1206: return("T_DEREF");
		case 0x1207: return("T_ADDROF");
		case 0x1208: return("T_NULL");
		case 0x1209: return("T_NEGATE");
		case 0x120A: return("T_FUNCCALL");
		case 0x120B: return("T_BOOL");
		case 0x120C: return("T_PAD");
		case 0x120D: return("T_CLEANUP");
		case 0x120E: return("T_CASELABEL");
		case 0x120F: return("T_ARGCOMMA");
		case 0x1210: return("T_REG");
		case 0x2000: return("T_USER");
		case 0x3FFF: return("T_LINE");
		default:     return(NULL);
	}
}

static void dump_tree(register struct node *n, unsigned depth)
{
	register unsigned i;
	char *name;
	if (n == NULL)
		return;
	for (i = 0; i < depth; i++)
		fputs("    ", stderr);
	name= getopname(n->op);
	if (name)
		fprintf(stderr, "%s v%lx t%x f%x ", name, n->value,
							 n->type, n->flags);
	else
		fprintf(stderr, "%04X v%lx t%x f%x ", n->op, n->value,
							n->type, n->flags);
	if (n->snum)
		fprintf(stderr, "\t%s", namestr(n->snum));
	fputc('\n', stderr);
	dump_tree(n->left, depth + 1);
	dump_tree(n->right, depth + 1);
}
#endif

static unsigned process_expression(void)
{
	register struct node *n = load_tree();
	unsigned t;
#ifdef DEBUG
	fprintf(stderr, ":load:\n");
	dump_tree(n, 0);
#endif
	n = gen_rewrite(n);
	n = rewrite_tree(n);
#ifdef DEBUG
	fprintf(stderr, ":rewritten:\n");
	dump_tree(n, 0);
#endif
	gen_tree(n);
	t = n->type;
	free_tree(n);
	return t;
}

static unsigned compile_expression(void)
{
	uint8_t h[2];
	unsigned t;
	/* We can end up with literal headers before the expression if the
	   expression is something like if (x = "eep"). Process up to and
	   including our expression */
	do {
		xread(0, h, 2);
		t = process_one_block(h);
	} while (h[1] != '^');
	return t;
}

/*
 *	Process the header blocks. We call out to the target to let it
 *	handle the needs of the platform.
 */

static unsigned func_ret;
static unsigned frame_len;
static unsigned argframe_len;
static unsigned func_ret_used;
unsigned func_flags;

static void process_literal(unsigned id)
{
	unsigned char c;
	register unsigned char shifted = 0;

	gen_literal(id);

	/* A series of bytes terminated by a 0 marker. Internal
	   zero is quoted, undo the quoting and turn it into data */
	while (1) {
		if (read(0, &c, 1) != 1)
			error("unexpected EOF");
		if (c == 0) {
			break;
		}
		if (c == 255 && !shifted) {
			shifted = 1;
			continue;
		}
		if (shifted && c == 254)
			c = 0;
		shifted = 0;
		gen_value(UCHAR, c);
	}
}

static void process_header(void)
{
	struct header h;
	static char tbuf[16];

	xread(0, &h, sizeof(struct header));

	switch (h.h_type) {
	case H_EXPORT:
		gen_export(namestr(h.h_name));
		break;
	case H_FUNCTION:
		push_area(A_CODE);
		gen_prologue(namestr(h.h_data));
		func_ret = h.h_name;
		func_ret_used = 0;
		break;
	case H_FRAME:
		frame_len = h.h_name;
		func_flags = h.h_data;
		gen_frame(h.h_name, argframe_len);
		break;
	case H_ARGFRAME:
		argframe_len = h.h_name;
		break;
	case H_FUNCTION | H_FOOTER:
		if (func_ret_used)
			gen_label("_r", h.h_name);
		gen_epilogue(frame_len, argframe_len);
		pop_area();
		break;
	case H_FOR:
		compile_expression();
		/* We will loop back to the conditional */
		gen_label("_l", h.h_name);
		/* A blank conditional on the for is a C oddity and means 'always true' */
		if (compile_expression() != VOID) {
			/* Exit the loop if false */
			gen_jfalse("_b", h.h_name);
		}
		/* Jump top the main body if not */
		gen_jump("_n", h.h_name);
		/* We continue with the final clause of the for */
		gen_label("_c", h.h_name);
		compile_expression();
		/* Then jump to the condition */
		gen_jump("_l", h.h_name);
		/* Body starts here */
		gen_label("_n", h.h_name);
		break;
	case H_FOR | H_FOOTER:
		gen_jump("_c", h.h_name);
		gen_label("_b", h.h_name);
		break;
	case H_WHILE:
		gen_label("_c", h.h_name);
		if (h.h_data == -1) {
			compile_expression();
			gen_jfalse("_b", h.h_name);
		} else if (h.h_data == 0)
			gen_jump("_b", h.h_name);
		/* And for the truth case just drop into the code */
		break;
	case H_WHILE | H_FOOTER:
		/* A while (0) has no loop branch */
		if (h.h_data != 0)
			gen_jump("_c", h.h_name);
		gen_label("_b", h.h_name);
		break;
	case H_DO:
		gen_label("_t", h.h_name);
		break;
	case H_DO | H_FOOTER:
		gen_jump("_t", h.h_name);
		gen_label("_b", h.h_name);
		break;
	case H_DOWHILE:
		gen_label("_c", h.h_name);
		if (h.h_data == -1) {
			compile_expression();
			gen_jtrue("_t", h.h_name);
		} else if (h.h_data == 1)
			gen_jump("_t", h.h_name);
		/* For while(0) just drop out */
		break;
	case H_DOWHILE | H_FOOTER:
		gen_label("_b", h.h_name);
		break;
	case H_BREAK:
		gen_jump("_b", h.h_name);
		break;
	case H_CONTINUE:
		gen_jump("_c", h.h_name);
		break;
	case H_IF:
		/* The front end tells us 0/1 false, true, or -1 for
		   expression. This will guide the code elimination in the
		   backend, which can throw code unless there are other
		   labels within. We can only eliminate simple stuff this way
		   as we just don't have the memory to spot a goto into a block
		   that is unreachable. In particular it is legal to goto the
		   middle of a block so we must put the branches in */
		if (h.h_data == -1) {
			compile_expression();
			gen_jfalse("_e", h.h_name);
		} else if (h.h_data == 0)
			gen_jump("_e", h.h_name);
		break;
	case H_ELSE:
		gen_jump("_f", h.h_name);
		if (h.h_data != 1)
			gen_label("_e", h.h_name);
		break;
	case H_IF | H_FOOTER:
		/* If we have an else then _f is needed, if not _e is */
		if (h.h_data)
			gen_label("_f", h.h_name);
		else
			gen_label("_e", h.h_name);
		break;
	case H_RETURN:
//              func_ret_used = 1;
		break;
	case H_RETURN | H_FOOTER:
		if (gen_exit("_r", func_ret) == 0)
			func_ret_used = 1;
		break;
	case H_LABEL:
		sprintf(tbuf, "_g%u", h.h_data);
		gen_label(tbuf, h.h_name);
		break;
	case H_GOTO:
		sprintf(tbuf, "_g%u", h.h_data);
		gen_jump(tbuf, h.h_name);
		break;
	case H_SWITCH:
		/* Generate the switch header, expression and table run */
		gen_switch(h.h_name, compile_expression());	/* need the type of it back */
		break;
	case H_CASE:
		gen_case_label(h.h_name, h.h_data);
		break;
	case H_DEFAULT:
		gen_case_label(h.h_name, 0);
		break;
	case H_SWITCH | H_FOOTER:
		gen_label("_b", h.h_data);
		break;
	case H_SWITCHTAB:
		push_area(A_LITERAL);
		gen_switchdata(h.h_name, h.h_data);
		break;
	case H_SWITCHTAB | H_FOOTER:
		pop_area();
		break;
	case H_DATA:
		push_area(A_DATA);
		if (h.h_name >= 0x8000)
			gen_data_label(namestr(h.h_name), h.h_data);
		else
			gen_literal(h.h_name);
		break;
	case H_DATA | H_FOOTER:
		pop_area();
		break;
	case H_BSS:
		push_area(A_BSS);
		if (h.h_name >= 0x8000)
			gen_data_label(namestr(h.h_name), h.h_data);
		else
			gen_literal(h.h_name);
		break;
	case H_BSS | H_FOOTER:
		pop_area();
		break;
	case H_STRING:
		if (h.h_data)
			push_area(A_LITERAL);
		else
			push_area(A_DATA);
		process_literal(h.h_name);
		break;
	case H_STRING | H_FOOTER:
		pop_area();
		break;
	default:
		error("bad hdr");
		break;
	}
}

/* Each data node is a one node tree right now. We ought to trim this down
   to avoid bloating the intermediate file */

void process_data(void)
{
	register struct node *n = load_tree();
	switch (n->op) {
	case T_PAD:
		gen_space(n->value);
		break;
	case T_LABEL:
		gen_text_data(n);
		break;
	case T_NAME:
		gen_name(n);
		break;
	case T_CASELABEL:
		gen_case_data(n->value, n->val2);
		break;
	default:
		gen_value(n->type, n->value);
		break;
	}
	free_node(n);
}

/*
 *	Helpers for the code generation whenever the target has no
 *	direct method
 */

void helper_type(register unsigned t, unsigned s)
{
	if (PTR(t))
		t = USHORT;
	switch (t) {
	case UCHAR:
		if (s)
			putchar('u');
	case CCHAR:
		putchar('c');
		break;
	case UINT:
		if (s)
			putchar('u');
	case CSHORT:
		break;
	case ULONG:
		if (s)
			putchar('u');
	case CLONG:
		putchar('l');
		break;
	case FLOAT:
		putchar('f');
		break;
	case DOUBLE:
		putchar('d');
		break;
	default:
		fflush(stdout);
		fprintf(stderr, "*** bad type %x\n", t);
		printf("\n;bad type %x\n", t);
	}
}

/*
 *	Generate a helper call according to the types
 *
 *	Would be nice to have an option to build C like helper calls
 */
void do_helper(register struct node *n, const char *h, unsigned t, unsigned s)
{
	/* A function call has a type that depends upon the call, but the
	   type we want is a pointer */
	if (n->op == T_FUNCCALL)
		n->type = PTRTO;
	gen_helpcall(n);
	fputs(h, stdout);
	/* Bool and cast are special as they type convert. In the case of
	   bool we care about the type below the bool, and the result is
	   always integer. In the case of a cast we care about everything */
	if (n->op == T_BOOL || n->op == T_BANG)
		helper_type(n->right->type, 0);
	else {
		if (n->op == T_CAST) {
			helper_type(n->right->type, 1);
			putchar('_');
		}
		helper_type(t, s);
	}
	gen_helptail(n);
	putchar('\n');
	gen_helpclean(n);
}

void helper(struct node *n, const char *h)
{
	do_helper(n, h, n->type, 0);
}

/* Sign of types matters */
void helper_s(struct node *n, const char *h)
{
	do_helper(n, h, n->type, 1);
}

void make_node(register struct node *n)
{
	/* Try the target code generator first, if not use helpers */
	if (gen_node(n))
		return;

	switch (n->op) {
	case T_NULL:
		/* Dummy 'no expression' node */
		break;
	case T_SHLEQ:
		helper(n, "shleq");
		break;
	case T_SHREQ:
		helper_s(n, "shreq");
		break;
	case T_PLUSPLUS:
		/* Avoid the post op cost if the result isn't used, as is
		   commonly the case */
		if (n->flags & NORETURN)
			helper(n, "pluseq");
		else
			helper(n, "postinc");
		break;
	case T_MINUSMINUS:
		if (n->flags & NORETURN)
			helper(n, "minuseq");
		else
			helper(n, "postdec");
		break;
	case T_EQEQ:
		n->flags |= ISBOOL;
		helper(n, "cceq");
		break;
	case T_LTLT:
		helper(n, "shl");
		break;
	case T_GTGT:
		helper_s(n, "shr");
		break;
	case T_OROR:
		/* Handled with branches in the tree walk */
		break;
	case T_ANDAND:
		/* Handled with branches in the tree walk */
		break;
	case T_PLUSEQ:
		helper(n, "pluseq");
		break;
	case T_MINUSEQ:
		helper(n, "minuseq");
		break;
	case T_SLASHEQ:
		helper_s(n, "diveq");
		break;
	case T_STAREQ:
		helper(n, "muleq");
		break;
	case T_HATEQ:
		helper(n, "xoreq");
		break;
	case T_BANGEQ:
		n->flags |= ISBOOL;
		helper(n, "ccne");
		break;
	case T_OREQ:
		helper(n, "oreq");
		break;
	case T_ANDEQ:
		helper(n, "andeq");
		break;
	case T_PERCENTEQ:
		helper_s(n, "remeq");
		break;
	case T_AND:
		helper(n, "band");
		break;
	case T_STAR:
		helper(n, "mul");
		break;
	case T_SLASH:
		helper_s(n, "div");
		break;
	case T_PERCENT:
		helper_s(n, "rem");
		break;
	case T_PLUS:
		helper(n, "plus");
		break;
	case T_MINUS:
		helper(n, "minus");
		break;
	case T_COLON:
	case T_QUESTION:
		/* We did the work in the code generator as it's not a simple
		   operator behaviour */
		break;
	case T_HAT:
		helper(n, "xor");
		break;
	case T_LT:
		n->flags |= ISBOOL;
		helper_s(n, "cclt");
		break;
	case T_GT:
		n->flags |= ISBOOL;
		helper_s(n, "ccgt");
		break;
	case T_LTEQ:
		n->flags |= ISBOOL;
		helper_s(n, "cclteq");
		break;
	case T_GTEQ:
		n->flags |= ISBOOL;
		helper_s(n, "ccgteq");
		break;
	case T_OR:
		helper(n, "or");
		break;
	case T_TILDE:
		helper(n, "cpl");
		break;
	case T_BANG:
		n->flags |= ISBOOL;
		helper(n, "not");
		break;
	case T_EQ:
		helper(n, "assign");
		break;
	case T_DEREF:
		helper(n, "deref");
		break;
	case T_NEGATE:
		helper(n, "negate");
		break;
	case T_FUNCCALL:
		/* This should never get used, if it does you'll need to
		   sort out the type handling for this case */
		helper(n, "callfunc");
		break;
	case T_CLEANUP:
		/* Should never occur except direct */
		error("tclu");
		break;
	case T_LABEL:
		helper(n, "const");
		/* Used for const strings */
		gen_text_data(n);
		break;
	case T_CAST:
		helper_s(n, "cast");
		break;
	case T_CONSTANT:
		helper(n, "const");
		gen_value(n->type, n->value);
		break;
	case T_COMMA:
		/* foo, bar - we evaulated foo and stacked it, now throw it away */
		/* Targets will normally shortcut this push/pop or peephole it */
		helper(n, "pop");
		break;
	case T_ARGCOMMA:
		/* Used for function arg chaining - just ignore */
		return;
	case T_BOOL:
		/* Check if we know it's already bool */
		n->flags |= ISBOOL;
		/* FIXME: we should run this through as a node in case it can inline */
		if (!(n->right && (n->right->flags & ISBOOL)))
			helper(n, "bool");
		break;
	case T_NAME:
		helper(n, "loadn");
		gen_name(n);
		break;
	case T_LOCAL:
		helper(n, "loadl");
		gen_value(PTRTO, n->value);
		break;
	case T_ARGUMENT:
		helper(n, "loada");
		gen_value(PTRTO, n->value);
		break;
	default:
		fprintf(stderr, "Invalid %04x\n", n->op);
		exit(1);
	}
}

/*
 *	Load the symbol table from the front end
 */

static void load_symbols(const char *path)
{
	uint8_t n[2];
	sym_fd = open(path, O_RDONLY);
	if (sym_fd == -1) {
		perror(path);
		exit(1);
	}
	xread(sym_fd, n, 2);
	max_name = n[0] | (n[1] << 8);
}

static unsigned process_one_block(register uint8_t *h)
{
	if (h[0] != '%')
		error("sync");
	/* We write a sequence of records starting %^ for an expression
	   %[ for data blocks and %H for a header. This helps us track any
	   errors and sync screwups when parsing */
	if (h[1] == '^')
		return process_expression();
	else if (h[1] == 'H')
		process_header();
	else if (h[1] == '[')
		process_data();
	else
		error("unknown block");
	return 0;
}

/*
 *	Helpers for the targets
 */

static unsigned codegen_label;

/*
 *	Some 'expressions' are actually flow changing things disguised
 *	as expressions. Deal with them above the processor specific level.
 */
static unsigned branching_operator(struct node *n)
{
	register unsigned op = n->op;
	if (op == T_OROR)
		return 1;
	if (op == T_ANDAND)
		return 2;
	if (op == T_COLON)
		return 3;
	if (op == T_QUESTION)
		return 4;
	return 0;
}

/*
 *	Perform a simple left right walk of the tree and feed the code
 *	to the node generator.
 */
void codegen_lr(register struct node *n)
{
	register unsigned o = branching_operator(n);

	/* Don't generate any tree that has no side effects and no return */
	if ((n->flags & (SIDEEFFECT | IMPURE | NORETURN)) == NORETURN)
		return;

	/* The case of NORETURN alone must be dealt with in the target code generators */

	/* Certain operations require special handling because the rule is
	   for partial evaluation only. Notably && || and ?: */
	if (o) {
		unsigned lab = codegen_label++;
		/*  foo ? a : b is a strange beast. At this point we have
		   foo in the work register so need do nothing, and let the
		   ? subtree resolve it */
		if (o == 4) {
			codegen_lr(n->left);
			codegen_lr(n->right);
			return;
		}
		if (o == 3) {
			gen_jfalse("L", lab);
			codegen_lr(n->left);
			gen_jump("LC", lab);
			gen_label("L", lab);
			codegen_lr(n->right);
			gen_label("LC", lab);
			return;
		} else {
/*			printf(";C %x F %x\n", n->op, n->flags); */
			/* Can use CC but must not flip the CC direction as
			   it will break our branch chains. TODO - fix this
			   in the main compiler pass - but it's not trivial */
			n->left->flags |= (n->flags & CCONLY);
			n->left->flags |= CCFIXED;
			n->right->flags |= (n->flags & CCONLY);
			n->right->flags |= CCFIXED;
		}
		/* TODO ? shortcut && and || if one side is constant */
		codegen_lr(n->left);
		if (o == 1)
			gen_jtrue("L", lab);
		else
			gen_jfalse("L", lab);
		codegen_lr(n->right);
		gen_label("L", lab);
		/* We don't build the node itself - it's not relevant */
		n->flags |= ISBOOL;
		return;
	}

	/* Allow the code generator to short cut the tree walk for things it
	   knows how to directly complete */
	if (gen_shortcut(n))
		return;

	if (n->left) {
		codegen_lr(n->left);
		/* See if we can direct generate this block. May recurse */
		if (gen_direct(n))
			return;
		if (!gen_push(n->left))
			helper(n->left, "push");
	} else {
		/* Single argument hook to generate stuff without pre-loading
		   right into working register */
		if (gen_uni_direct(n))
			return;
	}
	if (n->right)
		codegen_lr(n->right);
	make_node(n);
}

/*
 *	Entry point
 */

int main(int argc, char *argv[])
{
	uint8_t h[2];

	argv0 = argv[0];

	/* We can make this better later */
	if (argc != 5 && argc != 6)
		error("arguments");
	cpu = atoi(argv[2]);
	opt = *argv[3];
	if (isdigit(opt))
		opt -= '0';
	else if (opt == 's') {
		opt = 0;
		optsize = 1;
	} else
		error("invalid optimizer level");
	cpufeat = atol(argv[4]);
	if (argv[5])
		codeseg = argv[5];
	init_name_cache();
	load_symbols(argv[1]);
	init_nodes();

	gen_start();
	while (read(0, &h, 2) > 0) {
		process_one_block(h);
	}
	gen_end();
}
