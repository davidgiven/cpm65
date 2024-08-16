void cprintf(char *fmt, ...);

char *argv[]= { "unused", "-fish", "-cat", "owl" };
int argc= 4;

int main() {
  int i;

  for (i = 1; i < argc; i++) {
    cprintf("i is %d\n", i);
    if (*argv[i] != '-') break;
  }

  while (i < argc) {
    cprintf("leftover %s\n", argv[i]);
    i++;
  }

  return (0);
}
