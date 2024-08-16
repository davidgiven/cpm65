void cprintf(char *fmt, ...);
#define NULL ((void *)0)

struct foo {
  int val;
  struct foo *next;
};

struct foo head, mid, tail;

int main() {
  struct foo *ptr;
  tail.val= 20; tail.next= NULL;
  mid.val= 15; mid.next= &tail;
  head.val= 10; head.next= &mid;

  ptr= &head;
  cprintf("%d %d\n", head.val, ptr->val);
  cprintf("%d %d\n", mid.val, ptr->next->val);
  cprintf("%d %d\n", tail.val, ptr->next->next->val);
  return(0);
}
