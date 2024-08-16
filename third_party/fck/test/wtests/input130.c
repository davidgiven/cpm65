void cprintf(char *fmt, ...);

char *x= "foo";

int main() {
  cprintf("Hello " "world" "\n");
  return(0);
}
