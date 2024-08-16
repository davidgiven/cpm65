void cprintf(char *fmt, ...);

int a;

int main() {
  cprintf("%d\n", 24 % 9);
  cprintf("%d\n", 31 % 11);
  a= 24; a %= 9; cprintf("%d\n",a);
  a= 31; a %= 11; cprintf("%d\n",a);
  return(0);
}
