void printchar(int);
void printint(int);

static void print_int(int xx, int base, int sign) {
  static char digits[] = "0123456789abcdef";
  char buf[16];
  int i;
  unsigned int x;

  if (sign && (sign = xx < 0))
    x = -xx;
  else
    x = xx;

  i = 0;
  do {
    buf[i++] = digits[(unsigned int) (x % base)];
  } while ((x /= base) != 0);

  if (sign)
    buf[i++] = '-';

  while (--i >= 0)
    printchar(buf[i]);
}

// Print to the console. only understands %d, %x, %p, %s.
void cprintf(char *fmt, ...) {
  int i, c, locking;
  unsigned int *argp;
  char *s;

  if (fmt == 0)
    // panic("null fmt");
    return;

  argp = (unsigned int *) (void *) (&fmt + 1);

  for (i = 0; (c = fmt[i] & 0xff) != 0; i++) {
    if (c != '%') {
      printchar(c);
      continue;
    }
    c = fmt[++i] & 0xff;
    if (c == 0)
      break;
    switch (c) {
    case 'c':
      printchar((char) (*argp & 0xff)); argp++;
      break;
    case 'd':
      print_int(*argp++, 10, 1);
      break;
    case 'o':
      print_int(*argp++, 8, 1);
      break;
    case 'x':
    case 'p':
      print_int(*argp++, 16, 0);
      break;
    case 's':
      if ((s = (char *) *argp++) == 0)
	s = "(null)";
      for(; *s; s++)
        printchar(*s);
      break;
    case '%':
      printchar('%');
      break;
    default:
      // Print unknown % sequence to draw attention.
      printchar('%');
      printchar(c);
      break;
    }
  }
}
