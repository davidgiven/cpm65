/*
 * Copyright (c) 2022 Eugene P. <pieu@mail.ru>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 * 
 * Adapted to CP/M-65, Andreas Baumann, 2024
 */

#include <cpm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lib/screen.h"

#define WIDTH  12
#define HEIGHT 20

#define W (WIDTH + 2)
#define H (HEIGHT + 1)
#define WXH (W * H)

#define E '.'
#define F '#'

// Simple acceleration calculation (unplayable over 9000 points)
#define ACCEL (100 - score / 100)

/* Example: figure "J" rotation 0
 * 0b0100010001100000
 *
 * 0 1 0 0
 * 0 1 0 0
 * 0 1 1 0
 * 0 0 0 0
 */
uint16_t figure[][4] = {
	{0b0010001000100010, 0b0000111100000000, 0b0010001000100010, 0b0000111100000000}, // I
	{0b0010001001100000, 0b0000010001110000, 0b0110010001000000, 0b0000011100010000}, // J
	{0b0100010001100000, 0b0000011101000000, 0b0110001000100000, 0b0000000101110000}, // L
	{0b0110011000000000, 0b0110011000000000, 0b0110011000000000, 0b0110011000000000}, // O
	{0b0100011000100000, 0b0000001101100000, 0b0100011000100000, 0b0000001101100000}, // S
	{0b1110010000000000, 0b0010011000100000, 0b0000010011100000, 0b1000110010000000}, // T
	{0b0010011001000000, 0b0000110001100000, 0b0010011001000000, 0b0000110001100000}  // Z
};

uint8_t field[WXH];

struct player {
	uint8_t figure_index, rot, x, y;
} gp;

static void cr()
{
	cpm_printstring("\n\r");
}

static void fatal(char* msg) 
{
	cpm_printstring("Error: ");
	cpm_printstring(msg);
	cr();
	cpm_warmboot();
}

static uint8_t rnd;

void srand(uint8_t seed)
{
	rnd = seed;
}

uint8_t rand(void)
{
	rnd = rnd * 5 + 17;
	return rnd;
}

int init()
{
	// Init screen
	if(!screen_init())
		fatal("No SCREEN driver, exiting");
	screen_clear();
	screen_showcursor(0);		// invisible cursor

	// Init random generator
	srand(42);
	
	// Init field
	memset(field, E, WXH-W);


	/* Draw glass
	 *
	 * |  |
	 * |  |
	 * +--+
	 */
	uint8_t i;

	memset(field + WXH-W+1, '-', W-2);

	for (i = 0; i < H - 1; i++)
		field[i * W] = field[i * W + W-1] = '|';
	field[i * W] = field[i * W + W-1] = '+';

	return 0;
}

int figure_draw(char ch, struct player p)
{
	uint16_t mask = 0b1000000000000000;
	uint8_t x, y;

	for (y = 0; y < 4; y++) {
		for (x = 0; x < 4; x++) {
			if (figure[p.figure_index][p.rot] & mask) {
				int offset = (y + p.y) * W + x + p.x;

				if (ch == F && field[offset] != E)
					return 0;

				if (gp.x == p.x && gp.y == p.y && gp.rot == p.rot)
					field[offset] = ch;
			}
			mask >>= 1;
		}
	}

	return 1;
}

int remove_lines()
{
	int16_t x, y;
	uint16_t c, shift, lines = 0;
	
	for (y = 0; y < H - 1; y++) {
		for (x = 1, c = 0; x < W - 1; x++)
			if (field[y * W + x] == F)
				c++;

		if (c == W - 2) {
			lines++;
			memset(field + y*W + 1, 0, W - 2);
		}
	}
	// Full line(s) now filled with zeros
	if (!lines)
		return 0;

	// Remove them and move the blocks down
	for (x = 1; x < W - 1; x++) {
		shift = 0;
		for (y = H - 2; y >= 0; y--) {
			if (!field[y * W + x])
				shift++;
			if (shift) {
				if (field[y * W + x] == F)
					field[(y + shift) * W + x] = F;
				field[y * W + x] = E;
			}
		}
	}

	uint16_t score = 10;

	if (lines > 1)
		score += 20;
	if (lines > 2)
		score += 40;
	if (lines > 3)
		score += 80;

	return score;
}

void end(uint16_t score)
{
	screen_clear();
	printf("Final score: %d\n", score);
	cpm_warmboot();
}

void field_print(int score)
{
	uint8_t y, x, sy, sx;

        screen_getsize(&sx, &sy);
	sy = (sy - H) / 2;
	sx = (sx - W) / 2;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			screen_setcursor(sx+x, sy+y);
			screen_putchar(field[y * W + x]);
		}
	}

	screen_setcursor(sx, sy + H + 1);
	printf("Score: %d", score);
}

int main()
{
	uint16_t counter = 0;
	uint8_t drop = 0, draw_next = 1;
	uint8_t key = 0;
	uint16_t score = 0;
	struct player p;

	init();

	do {
		if (draw_next == 1) {
			draw_next = 0;

			gp.figure_index = rand() % 7;
			gp.x = W / 2 - 2;
			gp.y = 0;
			gp.rot = 0;

			drop = 0;
			counter = 0;
			score += remove_lines();

			if (!figure_draw(F, gp))
				break; // game over

			field_print(score);
		}

		p = gp;
		key = screen_getchar(10);

		switch (key) {
			case 'w':
			case 'W':
				p.rot = gp.rot == 3 ? 0 : gp.rot + 1;
				break;
			case 'a':
			case 'A':
				p.x = gp.x - 1;
				break;
			case 'd':
			case 'D':
				p.x = gp.x + 1;
				break;
			case ' ':
				// quickly lower
				if (!drop)
					drop = 1;
				break;
			case 's':
			case 'S':
				// lower slowly
				counter = 254;
				break;
		}

		/* TODO: sleep a little while, idle looping? */

		if (++counter > ACCEL)
			counter = 0;

		if (drop == 1 || !counter)
			p.y = gp.y + 1;

		if (gp.x == p.x && gp.y == p.y && gp.rot == p.rot)
			continue;

		figure_draw(E, gp);

		if (!figure_draw(F, p)) {
			p.x = gp.x;
			p.rot = gp.rot;
			if (drop == 1) {
				drop = 2;
				counter = ACCEL / 2;
			} else if (!figure_draw(F, p) && !counter)
				draw_next = 1;
		} else {
			gp = p;
			if (drop == 2)
				drop = 0; // Allow use drop key again
		}

		figure_draw(F, gp);
		field_print(score);
	} while (key != 27);

	screen_showcursor(1);		// visible cursor

	end(score);
}
