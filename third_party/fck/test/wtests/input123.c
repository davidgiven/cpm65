void cprintf(char *fmt, ...);

int main() {
  int x;
  for (x=0; x < 20; x++)
    switch(x) {
      case 2:
      case 3:
      case 5:
      case 7:
      case 11: cprintf("%d infant prime\n", x); break;
      case 13:
      case 17:
      case 19: cprintf("%d teen   prime\n", x); break;
      case 0:
      case 1:
      case 4:
      case 6:
      case 8:
      case 9:
      case 10:
      case 12: cprintf("%d infant composite\n", x); break;
      default: cprintf("%d teen   composite\n", x); break;
    }

  return(0);
}
