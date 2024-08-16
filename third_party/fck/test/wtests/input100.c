void cprintf(char *fmt, ...);
int main() {
  int x= 3, y=14;
  int z= 2 * x + y;
  char *str= "Hello world";
  cprintf("%s %d %d\n", str, x+y, z);
  return(0);
}
