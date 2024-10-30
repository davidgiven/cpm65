/*
 * Mandelbrot for CP/M-65
 *
 * Adapted from https://github.com/Johnlon/mandelbrot/blob/main/integer.c
 * by Henrik Löfgren 2024.
 * 
 */

#include <stdio.h>
#include <cpm.h>
#include "lib/screen.h"

int main()
{	
    int width, height;
    int X1, X2, Y1, Y2, LIMIT;
    int px, py;
    int x0, y0;
    int x,y,i;
    int xSqr, ySqr;
    int sum;
    int xt;

    char * chr = ".,_-*!$&0 ";
	
    int maxIters = 10;

    if(!screen_init()) {
        cpm_printstring("Error: No SCREEN driver, exiting\r\n");
        cpm_warmboot();
    }
    screen_getsize(&width, &height);

    screen_clear();
    screen_setcursor(0,0);

    // 6 bit precision fixed point
    X1 = 224;
    X2 = 160;
    Y1 = 128;
    Y2 = 64;
    LIMIT = 512;
    px=0; 
    py=0;
    
    while (py < height) {
        while (px < width) {

            x0 = ((px*X1) / width) - X2;
            y0 = ((py*Y1) / height) - Y2;

            x=0;
            y=0;

            i=0;

            while (i < maxIters) {
                xSqr = (x * x) >> 6;
                ySqr = (y * y) >> 6;

                sum =(xSqr + ySqr);
                if (sum > LIMIT) { 
                    break;
                }

                xt = xSqr - ySqr + x0;

                y = (((x * y) >> 6) << 1) + y0;
                x=xt;
    
                i = i + 1;
            }
            i = i - 1;
            screen_putchar(chr[i]);
            px = px + 1;
        }

        cpm_printstring("\r\n");
        py = py + 1;
        px = 0;
    } 
	
	return 0;
}
