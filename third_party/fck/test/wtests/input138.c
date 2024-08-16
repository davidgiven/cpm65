void cprintf(char *fmt, ...);
#define NULL ((void *)0)

int x, y, z;

int a=1;
int *aptr;

int main() {

  // See if generic AND works
  for (x=0; x <= 1; x++)
    for (y=0; y <= 1; y++) {
      z= x && y;
      cprintf("%d %d | %d\n", x, y, z);
    }

  // See if generic AND works
  for (x=0; x <= 1; x++)
    for (y=0; y <= 1; y++) {
      z= x || y;
      cprintf("%d %d | %d\n", x, y, z);
    }

  // Now some lazy evaluation
  aptr= NULL;
  if (aptr && *aptr == 1)
    cprintf("aptr points at 1\n");
  else
    cprintf("aptr is NULL or doesn't point at 1\n");

  aptr= &a;
  if (aptr && *aptr == 1)
    cprintf("aptr points at 1\n");
  else
    cprintf("aptr is NULL or doesn't point at 1\n");

  return(0);
}
