void cprintf(char *fmt, ...);

int add(int x, int y) {
  return(x+y);
}

int main() {
  int result;
  result= 3 * add(2,3) - 5 * add(4,6);
  cprintf("%d\n", result);
  return(0);
}
