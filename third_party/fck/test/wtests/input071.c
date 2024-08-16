void cprintf(char *fmt, ...);

int main() {
  int x;
  x = 0;
  while (x < 100) {
    if (x == 5) { x = x + 2; continue; }
    cprintf("%d\n", x);
    if (x == 14) { break; }
    x = x + 1;
  }
  cprintf("Done\n");
  return (0);
}
