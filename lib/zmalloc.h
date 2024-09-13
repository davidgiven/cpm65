#pragma once
#include <stddef.h>

void zmalloc_init(void *start, size_t size);
void *zmalloc(size_t size);
void *zcalloc(size_t nmemb, size_t size);
void zfree(void *ptr);
void *zrealloc(void *ptr, size_t size);

#ifdef ZMALLOC_DEBUG
void print_memory(void);
#endif
