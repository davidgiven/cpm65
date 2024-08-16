/*
 * This file lifted in toto from 'Dlibs' on the atari ST  (RdeBath)
 *
 * 
 *    Dale Schumacher                         399 Beacon Ave.
 *    (alias: Dalnefre')                      St. Paul, MN  55104
 *    dal@syntel.UUCP                         United States of America
 *  "It's not reality that's important, but how you perceive things."
 */

/*
 * Sun Feb  8 21:02:15 EST 1998 claudio@pos.inf.ufpr.br (Claudio Matsuoka)
 * Changed sort direction
 */

#define	PIVOT			((i+j)>>1)

int compare(int *a, int *b)
{
   if (*a < *b)
      return -1;
   if (*a > *b)
      return 1;
   return 0;
}

static unsigned depth = 0;

int wqsort(void *basep, int lo, int hi)
{
   int   k;
   register int i, j, t;
   register int *p = &k;
   short *base = basep;

   depth++;
   if (depth > 64)
      return 1;

   while (hi > lo)
   {
      i = lo;
      j = hi;
      t = PIVOT;
      *p = base[t];
      base[t] = base[i];
      base[i] = *p;
      while (i < j)
      {
	 while ((compare ((base + j), p)) > 0)
	    --j;
	 base[i] = base[j];
	 while ((i < j) && ((compare((base + i), p)) <= 0))
	    ++i;
	 base[j] = base[i];
      }
      base[i] = *p;
      if ((i - lo) < (hi - i))
      {
	 if (wqsort(base, lo, (i - 1)))
	    return 1;
	 lo = i + 1;
      }
      else
      {
	 if (wqsort(base, (i + 1), hi))
	    return 1;
	 hi = i - 1;
      }
   }
   depth--;
   return 0;
}

static int table[2] = {
   1, 2
};

static int table2[2] = {
   2, 1
};

int main(int argc, char *argv[])
{
   if (compare(table, table2) != -1)
      return 1;
   if (compare(table2, table) != 1)
      return 2;
   if (compare(table2, table + 1) != 0)
      return 3;
   if (wqsort(table, 0, 1))
      return 4;
   if (wqsort(table2, 0, 1))
      return 5;
   if (table[0] != 1 || table[1] != 2)
      return 6;
   if (table2[0] != 1 || table2[1] != 2)
      return 7;
   return 0;
}
