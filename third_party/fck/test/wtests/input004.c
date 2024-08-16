void printint(int x);
void putchar(int ch);

int main()
{
  int x;
  x= 7 < 9;  printint(x);
  x= 7 <= 9; printint(x);
  x= 7 != 9; printint(x);
  x= 7 == 7; printint(x);
  x= 7 >= 7; printint(x);
  x= 7 <= 7; printint(x);
  x= 9 > 7;  printint(x);
  x= 9 >= 7; printint(x);
  x= 9 != 7; printint(x);
  return(0);
}
