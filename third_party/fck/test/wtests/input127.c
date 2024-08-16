void cprintf(char *fmt, ...);

int ary[5];

void fred(int *ptr) {		// Receive a pointer
  cprintf("%d\n", ptr[3]);
}

int main() {
  ary[3]= 2008;
  cprintf("%d\n", ary[3]);
  fred(ary);			// Pass ary as a pointer
  return(0);
}
