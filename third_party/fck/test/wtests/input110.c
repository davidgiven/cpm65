void cprintf(char *fmt, ...);

int x;
int y;

int main() {
  x= 3; y= 15; y += x; cprintf("%d\n", y);
  x= 3; y= 15; y -= x; cprintf("%d\n", y);
  x= 3; y= 15; y = y * x; cprintf("%d\n", y);
  x= 3; y= 15; y /= x; cprintf("%d\n", y);
  return(0);
}
