void cprintf(char *fmt, ...);

void donothing() { }

int main() {
  int x=0;
  cprintf("Doing nothing... "); donothing();
  cprintf("nothing done\n");

  while (++x < 100) ;
  cprintf("x is now %d\n", x);

  return(0);
}
