void cprintf(char *fmt, ...);

char *str= "qwertyuiop";

int list[]= {3, 5, 7, 9, 11, 13, 15};

int *lptr;

int main() {
  cprintf("%c\n", *str);
  str= str + 1; cprintf("%c\n", *str);
  str += 1; cprintf("%c\n", *str);
  str += 1; cprintf("%c\n", *str);
  str -= 1; cprintf("%c\n", *str);

  lptr= list;
  cprintf("%d\n", *lptr);
  lptr= lptr + 1; cprintf("%d\n", *lptr);
  lptr += 1; cprintf("%d\n", *lptr);
  lptr += 1; cprintf("%d\n", *lptr);
  lptr -= 1; cprintf("%d\n", *lptr);
  return(0);
}
