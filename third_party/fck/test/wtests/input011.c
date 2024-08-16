void printint(int x);
void putchar(int ch);

int main()
{
  int i; char j; long k;

  i= 10; printint(i);
  j= 20; printint(j);
  k= 30; printint(k);

  for (i= 1;   i <= 5; i= i + 1) { printint(i); }
  for (j= 253; j != 4; j= j + 1) { printint(j); }
  for (k= 1;   k <= 5; k= k + 1) { printint(k); }
  return(0);
  printint(12345);
  return(3);
}
