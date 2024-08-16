void cprintf(char *fmt, ...);
#define NULL ((void *)0)

struct Svalue {
  char *thing;
  int vreg;
  int intval;
};

struct IR {
  int label;
  int op;
  struct Svalue dst;
  struct Svalue src1;
  struct Svalue src2;
  int jmplabel;
};

struct foo {
  int a;
  int b;
  struct Svalue *c;
  int d;
};

struct IR *fred;
struct IR jim;
struct foo jane;
struct Svalue dave;

int main() {
  fred= &jim;
  fred->label= 1;
  fred->op= 2;
  fred->dst.thing= NULL;
  fred->dst.vreg=3;
  fred->dst.intval=4;
  fred->src1.thing= NULL;
  fred->src1.vreg=5;
  fred->src1.intval=6;
  fred->src2.thing= NULL;
  fred->src2.vreg=7;
  fred->src2.intval=8;
  fred->jmplabel= 9;

  cprintf("%d %d %d\n",   fred->label, fred->op, fred->dst.vreg);
  cprintf("%d %d %d\n",   fred->dst.intval, fred->src1.vreg, fred->src1.intval);
  cprintf("%d %d %d\n\n", fred->src2.vreg, fred->src2.intval, fred->jmplabel);

  jane.c= &dave;
  jane.a= 1; jane.b= 2; jane.d= 4; 
  jane.c->thing= "fish";
  jane.c->vreg= 3;
  jane.c->intval= 5;

  cprintf("%d %d %d\n", jane.a, jane.b, jane.c->vreg);
  cprintf("%d %d %s\n", jane.d, jane.c->intval, jane.c->thing);

  return(0);
}
