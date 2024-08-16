#define NULL ((void *)0)
void cprintf(char *fmt, ...);

char* y = NULL;
int x= 10 + 6;
int fred [ 2 + 3 ];

int main() {
  fred[2]= x;
  cprintf("%d\n", fred[2]);
  return(0);
}
