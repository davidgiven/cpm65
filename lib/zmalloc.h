#pragma once
#include <stddef.h>
#include <stdint.h>

void zmalloc_init(void *start, size_t size, uint8_t realloc_free_minsize);
void *zmalloc(size_t size);
void *zcalloc(size_t nmemb, size_t size);
void zfree(void *ptr);
void *zrealloc(void *ptr, size_t size);

#ifdef ZMALLOC_DEBUG
void print_memory(void);
void check_memory(void);
#endif
