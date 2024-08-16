void cprintf(char *fmt, ...);

int a = 23, b = 100;
char y = 'H', *z = "Hello world";

int main() {
  cprintf("%d %d %c %s\n", a, b, y, z);
  return (0);
}
