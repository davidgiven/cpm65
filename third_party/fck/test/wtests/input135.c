void cprintf(char *fmt, ...);

void fred() {
  int x= 5;
  cprintf("testing x\n");
  if (x > 4) return;
  cprintf("x below 5\n");
}

int main() {
  fred();
  return(0);
}
