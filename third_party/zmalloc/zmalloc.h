#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifndef SIZE_MAX
#define SIZE_MAX    ((size_t)-1)
#endif

bool zmalloc_init(void *start, size_t size);
void *zmalloc(size_t size);
void *zcalloc(size_t nmemb, size_t size);
void zfree(void *ptr);
void *zrealloc(void *ptr, size_t size);
void *zaligned_alloc(size_t alignment, size_t size);
int zposix_memalign(void **memptr, size_t alignment, size_t size);

#ifdef ZMALLOC_DEBUG
void print_memory(void);
#endif
