void cprintf(char *fmt, ...);
#define NULL ((void *)0)

char foo;
char *a, *b, *c;

int main() {

  a= b= c= NULL;
  if (a==NULL || b==NULL || c==NULL)
    cprintf("One of the three is NULL\n");
  a= &foo;
  if (a==NULL || b==NULL || c==NULL)
    cprintf("One of the three is NULL\n");
  b= &foo;
  if (a==NULL || b==NULL || c==NULL)
    cprintf("One of the three is NULL\n");
  c= &foo;
  if (a==NULL || b==NULL || c==NULL)
    cprintf("One of the three is NULL\n");
  else
    cprintf("All  three  are non-NULL\n");

  return(0);
}
