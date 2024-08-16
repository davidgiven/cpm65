void cprintf(char *fmt, ...);

int x;
int y= 3;

int main() {
  x= y != 3 ? 6 : 8; cprintf("%d\n", x);
  x= (y == 3) ? 6 : 8; cprintf("%d\n", x);
  return(0);
}
