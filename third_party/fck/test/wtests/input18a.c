void printint(int x);
void putchar(int ch);

int   a;
int  *b;
char  c;
char *d;

int main()
{
  b= &a; *b= 15; printint(a);
  d= &c; *d= 16; printint(c);
  return(0);
}
