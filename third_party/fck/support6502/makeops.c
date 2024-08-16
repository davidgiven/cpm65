#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void write_ysubop(const char *path, const char *op, const char *end, const char *pre)
{
    FILE *f = fopen(path, "w");
    if (f == NULL) {
        perror(path);
        exit(1);
    }
    
    fprintf(f, "\t.code\n\n");
    fprintf(f, "\t.export __%s%sy0\n\t.export __%s%sy0s\n", op, end, op, end);
    fprintf(f, "\t.export __%s%sy\n\t.export __%s%sys\n", op, end, op, end);
    fprintf(f, "__%s%sy0:\n", op, end);
    fprintf(f, "__%s%sy0s:\n", op, end);
    fprintf(f, "\tldy #0\n");
    fprintf(f, "__%s%sy:\n", op, end);
    fprintf(f, "__%s%sys:\n", op, end);
    if (pre)
        fprintf(f, "\t%s\n", pre);
    fprintf(f, "\t%s (@%s),y\n", op, end);
    fprintf(f, "\tpha\n\ttxa\n\tiny\n");
    fprintf(f, "\t%s (@%s),y\n", op, end);
    fprintf(f, "\ttax\n\tpla\n\trts\n");
    fclose(f);
}

void write_yop(const char *op, const char *pre)
{
    char buf[64];
    snprintf(buf, 64, "__%sspy.s", op);
    write_ysubop(buf, op, "sp", pre);
    snprintf(buf, 64, "__%stmpy.s", op);
    write_ysubop(buf, op, "tmp", pre);
}

void write_c8_op(const char *op, const char *pre)
{
    char buf[64];
    FILE *f;
    snprintf(buf, 64, "__%sc8.s", op);
    f = fopen(buf, "w");
    if (f == NULL) {
        perror(buf);
        exit(1);
    }
    fprintf(f, "\t.code\n\n");
    fprintf(f, "\t.export __%sc8\n\t.export __%sc8s\n", op, op);
    fprintf(f, "__%sc8:\n", op);
    fprintf(f, "__%sc8s:\n", op);
    fprintf(f, "\tsty @tmp\n");
    if (pre)
        fprintf(f, "\t%s\n", pre);
    fprintf(f, "\t%s @tmp\n", op);
    if (strcmp(op, "adc") == 0) {
        fprintf(f, "\tbcc l1\n");
        fprintf(f, "\tinx\n");
        fprintf(f, "l1:\n");
    }
    if (strcmp(op, "sbc") == 0) {
        fprintf(f, "\tbcs l1\n");
        fprintf(f, "\tdex\n");
        fprintf(f, "l1:\n");
    }
    fprintf(f, "\trts\n");
}

void write_tmpop(const char *op, const char *pre)
{
    char buf[64];
    FILE *f;
    snprintf(buf, 64, "__%stmp.s", op);

    f = fopen(buf, "w");
    if (f == NULL) {
        perror(buf);
        exit(1);
    }
    
    fprintf(f, "\t.code\n\n");
    fprintf(f, "\t.export __%s\n\t.export __%ss\n", op, op);
    fprintf(f, "\t.export __%stmp\n\t.export __%stmps\n", op, op);
    fprintf(f, "__%s:\n", op);
    fprintf(f, "__%ss:\n", op);
    fprintf(f, "\tjsr __poptmp\n");
    fprintf(f, "__%stmp:\n", op);
    fprintf(f, "__%stmps:\n", op);
    if (pre)
        fprintf(f, "\t%s\n", pre);
    fprintf(f, "\t%s @tmp\n", op);
    fprintf(f, "\tpha\n\ttxa\n");
    fprintf(f, "\t%s @tmp+1\n", op);
    fprintf(f, "\ttax\n\tpla\n\trts\n");
    fclose(f);
}

/* This writes all the usual word forms of
        a += b
   We don't do <<= or >>= here as they are a bit different.
   We don't do -= because it needs to be done the other way around

   On entry @tmp is the left side (addr), and the value is the modifier.
   On exit XA is the result
*/

void write_eqtmpop(const char *op, const char *pre)
{
    char buf[64];
    FILE *f;
    snprintf(buf, 64, "__%seqtmp.s", op);

    f = fopen(buf, "w");
    if (f == NULL) {
        perror(buf);
        exit(1);
    }
    
    fprintf(f, "\t.code\n\n");
    fprintf(f, "\t.export __%stmp\n\t.export __%stmps\n", op, op);
    fprintf(f, "__%stmp:\n", op);
    fprintf(f, "__%stmps:\n", op);
    fprintf(f, "\tldy #0\n");
    if (pre)
        fprintf(f, "\t%s\n", pre);
    fprintf(f, "\t%s (@tmp),y\n", op);
    fprintf(f, "\tsta (@tmp),y\n");
    fprintf(f, "\tpha\n\ttxa\n\tiny\n");
    fprintf(f, "\t%s (@tmp),y\n", op);
    fprintf(f, "\tsta (@tmp),y\n");
    fprintf(f, "\ttax\n\tpla\n\trts\n");
    fclose(f);
}

int main(int argc, char *argv[])
{
    write_yop("adc", "clc");
    write_yop("sbc", "sec");
    write_yop("and", NULL);
    write_yop("ora", NULL);
    write_yop("eor", NULL);
    write_yop("lda", NULL);
    write_yop("sta", NULL);

    write_tmpop("adc", "clc");
    write_tmpop("sbc", "sec");
    write_tmpop("and", NULL);
    write_tmpop("ora", NULL);
    write_tmpop("eor", NULL);

    write_eqtmpop("adc", "clc");
    /* sbc is not commutive */
/*    write_eqtmpop("sbc", "sec"); */
    write_eqtmpop("and", NULL);
    write_eqtmpop("ora", NULL);
    write_eqtmpop("eor", NULL);
    
    return 0;
}
