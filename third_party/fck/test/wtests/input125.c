void cprintf(char *fmt, ...);

int ary[5];
int *ptr;
int x;

int main() {
  ary[3]= 2008;
  ptr= ary;			// Load ary's address into ptr
  x= ary[3]; cprintf("%d\n", x);
  x= ptr[3]; cprintf("%d\n", x); // Treat ptr as an array
  return(0);
}
