void cprintf(char *fmt, ...);

void fred(int x) {
  int a = 2;
  int *b = &x;
  cprintf("%d %d %d\n", x, a, *b);
}

int main() {
  fred(4);
  return(0);
}
