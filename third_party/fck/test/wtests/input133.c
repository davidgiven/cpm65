void cprintf(char *fmt, ...);

extern int fred[];
int fred[23];

char mary[100];
extern char mary[];

void main() { cprintf("OK\n"); }
