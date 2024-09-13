/*
 * Simple first-fit memory allocator for a fixed size memory pool
 *
 * Copyright © 2024 by Ivo van Poorten
 * BSD0 License
 *
 */

#include <stdbool.h>
#include <string.h>     // memset, memcpy
#include <stdlib.h>     // abort

// Round up, use to avoid constant copies on ascending realloc sizes and
// reduce memory fragmentation
//
//#define ROUNDUP(x)  x                   // no roundup
//#define ROUNDUP(x)  (((x)+3) & -4)      // nearest multiple of 4

#define ROUNDUP(x)  (((x)+7) & -8)        // nearest multiple of 8
#define MINSIZE 8                         // used during realloc

//#define ROUNDUP(x)  (((x)+15) & -16)    // nearest multiple of 16
//#define ROUNDUP(x)  (((x)+31) & -32)    // nearest multiple of 32

static void *base;

struct block_info;

struct __attribute__((packed)) block_info {
    bool free;
    size_t size;
    struct block_info *prev;
    struct block_info *next;
};

#define block_info_size (sizeof(struct block_info))

void zmalloc_init(void *start, size_t size) {
    base = start;
    struct block_info *p = base;
    p->free = 1;
    p->size = size - block_info_size;
    p->prev = p->next = NULL;
}

void *zmalloc(size_t size) {
    if (!size) return NULL;

    size = ROUNDUP(size);

    struct block_info *p;

    for (p = base; p && !(p->free && p->size >= size); p = p->next) ; // find
    if (!p) return NULL;

    if (p->size - size > block_info_size) {
#if 1
        // split, alloc at begin
        struct block_info *q = (void *) p + block_info_size + size;
        q->next = p->next;
        p->next = q;
        q->prev = p;
        if (q->next) q->next->prev = q;
        q->size = p->size - block_info_size - size;
        p->size = size;
        q->free = 1;
#endif
#if 0
        // split, alloc at end
        struct block_info *q = (void *) p + p->size - size;
        p->size -= size + block_info_size;
        q->size = size;
        q->next = p->next;
        p->next = q;
        q->prev = p;
        if (q->next) q->next->prev = q;
        p = q;
#endif
    }

    p->free = 0;
    return (void *) p + block_info_size;
}

void *zcalloc(size_t nmemb, size_t size) {
    size_t nsize = nmemb * size;
    void *p = zmalloc(nsize);
    if (p) memset(p, 0, nsize);
    return p;
}

static void merge_with_next_free(struct block_info *p) {
    if (p->next && p->next->free) {
        struct block_info *q = p->next;
        p->size += q->size + block_info_size;
        p->next = q->next;
        if (p->next) p->next->prev = p;
    }
}

void __zfree_null(void);

void zfree(void *ptr) {
    if (!ptr) __zfree_null();

    struct block_info *p = ptr - block_info_size;
    p->free = 1;

    if (p->prev && p->prev->free) {    // if free, merge with previous block
        struct block_info *q = p->prev;
        q->size += p->size + block_info_size;
        q->next = p->next;
        if (q->next) q->next->prev = q;
        p = q;
    }
    merge_with_next_free(p);
}

void *zrealloc(void *ptr, size_t size) {
    if (!ptr) return zmalloc(size);
    if (!size) { zfree(ptr); return NULL; }

    size = ROUNDUP(size);

    struct block_info *p = (void *) ptr - block_info_size;

    if (size > p->size) { // bigger
        // allocate new, copy, and free old
        void *q = zmalloc(size);
        if (!q) return NULL;
        memcpy(q, ptr, p->size);
        zfree(ptr);
        return q;
    } else if (p->size > size + block_info_size + MINSIZE) { // smaller enough
        // split and create new free block
        struct block_info *q = (void *) p + block_info_size + size;
        q->next = p->next;
        p->next = q;
        q->prev = p;
        if (q->next) q->next->prev = q;
        q->size = p->size - block_info_size - size;
        p->size = size;
        q->free = 1;
        merge_with_next_free(q);
    }
    return ptr;
}

#ifdef ZMALLOC_DEBUG
#include <stdio.h>
void print_memory(void) {
    struct block_info *p;
    for (int c = 0, p = base ; p ; p = p->next, c++)
        printf("block %d, %s, size: %ld\n", c, p->free ? "free" : "used", p->size);
}
#endif
