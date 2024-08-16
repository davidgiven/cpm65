
int check(const char *dummy, int a, int b)
{
  if (a != 3 || b != 3)
    return 1;
  return 0;
}

int main(void) {
  static char gt[30];
  char *p;
  p= gt;

  *p++ = 'W';
  *p++ = 'K';
  *p++ = 'T';

  if (check("", (p-gt), (p-gt)))
    return 1;
  return 0;
}
