void printint(int x);

int main() {
  int   d;
  int  *e;

  d= 100;
  e= &d;
  *e= 12;
  printint(d);
  return(0);
}
