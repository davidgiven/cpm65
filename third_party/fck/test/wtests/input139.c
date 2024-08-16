void cprintf(char *fmt, ...);

int same(int x) { return(x); }

int main() {
  int a= 3;

  if (same(a) && same(a) >= same(a))
    cprintf("same apparently\n");
  return(0);
}
