void cprintf(char *fmt, ...);
#define NULL ((void *)0)

char y = 'a';
char *x;

int main() {
  x= &y;        if (x && y == 'a') cprintf("1st match\n");
  x= NULL;      if (x && y == 'a') cprintf("2nd match\n");
  x= &y; y='b'; if (x && y == 'a') cprintf("3rd match\n");
  return(0);
}
