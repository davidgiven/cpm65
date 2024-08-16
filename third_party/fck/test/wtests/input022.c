// ++ tests
void cprintf(char *fmt, ...);

int main() {
  char *str= "1234567";
  int sum;

  sum= 10; sum= sum * 10;          cprintf("%d\n", sum);

  // This one doesn't work as at commit 1ba062c
  sum= 10; sum *= 10;              cprintf("%d\n", sum);

  sum = sum + (*str - '0'); str++; cprintf("%d\n", sum);
  sum += *str++ - '0';             cprintf("%d\n", sum);

  return(0);
}
