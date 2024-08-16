void cprintf(char *fmt, ...);

static char *fred(void) {
  return("Hello");
}

int main(void) {
  cprintf("%s\n", fred());
  return(0);
}
