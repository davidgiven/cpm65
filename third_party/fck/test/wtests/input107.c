void cprintf(char *fmt, ...);
#define NULL ((void *)0)

char *y[] = { "fish", "cow", NULL };
char *z= NULL;

int main() {
  int i;
  char *ptr;
  for (i=0; i < 3; i++) {
    ptr= y[i];
    if (ptr != (char *)0)
      cprintf("%s\n", y[i]);
    else
      cprintf("NULL\n");
  }
  return(0);
}
