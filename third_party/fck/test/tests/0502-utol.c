static char buf[34];

char * __ultostr(unsigned long val, int radix)
{
   register char *p;
   register int c;

   if( radix > 36 || radix < 2 ) return 0;

   p = buf+sizeof(buf);
   *--p = '\0';

   do
   {
      c = val%radix;
      val/=radix;
      if( c > 9 ) *--p = 'a'-10+c; else *--p = '0'+c;
   }
   while(val);
   return p;
}

char * __ltostr(long val, int radix)
{
   char *p;
   int flg = 0;
   if( val < 0 ) { flg++; val= -val; }
   p = __ultostr(val, radix);
   if(p && flg) *--p = '-';
   return p;
}


int main(int argc, char *argv[])
{
   char *p = __ltostr(-31995, 10);
   char *n = p;
/*   while(*n)
      print(*n++); */
   if (*p != '-' || p[1] != '3' || p[2] != '1' ||  p[3] != '9' || p[4] != '9' || p[5] != '5' || p[6])
      return 1;
   return 0;
}
