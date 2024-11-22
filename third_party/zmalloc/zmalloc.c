/*
 * ZMALLOC - Dynamic Memory Allocation for Small Memory Systems
 *
 * Copyright © 2024 by Ivo van Poorten
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/* See also:
 * Dynamic Storage Allocation: A Survey and Critical Review
 * by Paul R. Wilson, Mark S. Johnstone, Michael Neely, and David Boles
 * International Workshop on Memory Management, September 1995
 * ftp://ftp.cs.utexas.edu/pub/garbage/allocsrv.ps
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

struct block_info;
struct block_info {
    uintptr_t size;
    struct block_info *prev;
    struct block_info *next;
};

static void *base;
static struct block_info *free_list;
static const uintptr_t minfreeblocksize = sizeof(struct block_info);

#define is_free(x)   (!((x)& 1))
#define is_inuse(x)    ((x)& 1)
#define set_free(x)    ((x)&~1)
#define set_inuse(x)   ((x)| 1)
#define get_size(x)    ((x)&-sizeof(uintptr_t))

static inline void *align_up(void *p, int to) {
    return (void *)(((uintptr_t) p + to - 1) & -to);
}

bool zmalloc_init(void *start, size_t size) {
    static_assert(sizeof(uintptr_t) == sizeof(void *), "uintptr_t mismatch");

    base = align_up(start, sizeof(uintptr_t));     // align our memory pool
    size -= base - start;               // adjust size for skipped mememory
    size &= -sizeof(uintptr_t);            // reduce size to multiple of alignment

    if (size < 3 * sizeof(struct block_info)) return false;

    // setup sentinels, size is 0, prev = next = NULL
    struct block_info *begin = base;
    struct block_info *end   = base + size - sizeof(struct block_info);
    memset(begin, 0, sizeof(struct block_info));
    memset(end, 0, sizeof(struct block_info));
    size -= 2 * sizeof(struct block_info);    // subtract from available memory

    // one free block
    struct block_info *freeb = base + sizeof(struct block_info);
    freeb->size = size;

    // setup free_list as begin <-> freeb <-> end
    freeb->prev = free_list = begin;
    freeb->next = end;
    begin->next = end->prev   = freeb;

    return true;
}

static size_t size_requirements(size_t size) {
    size += sizeof(uintptr_t);
    size = (size_t) align_up((void *)size, sizeof(uintptr_t));

    if (size < sizeof(struct block_info))
        size = sizeof(struct block_info);

    return size;
}

void *zmalloc(size_t size) {
    if (!size) {
        errno = ENOMEM;
        return NULL;
    }

    size = size_requirements(size);

    struct block_info *p = free_list->next;     // skip sentinel

    while (p && p->size < size)
        p = p->next;

    if (!p) {
        errno = ENOMEM;
        return NULL;
    }

    if (p->size - size > minfreeblocksize) { // split
        struct block_info *freeb = (void *) p + size;
        freeb->size = p->size - size;

        // link free block into free_list in place of p
        freeb->prev = p->prev;
        freeb->next = p->next;
        freeb->prev->next = freeb;
        freeb->next->prev = freeb;
        // reduce alloc size to size
        p->size = size;
    } else {                                // take full block
        // unlink from free_list
        p->prev->next = p->next;
        p->next->prev = p->prev;
    }

    p->size = set_inuse(p->size);

    return (void *) p + sizeof(uintptr_t);
}

void *zcalloc(size_t nmemb, size_t size) {
    if (nmemb && size > (size_t)-1/nmemb) { // check overflow of multiplication
        errno = ENOMEM;
        return 0;
    }
    size_t nsize = nmemb * size;
    void *p = zmalloc(nsize);
    if (p) memset(p, 0, nsize);
    return p;
}

static void link_to_free_list(struct block_info *p) {
    struct block_info *nextb = (void *) p + p->size;

    if (is_free(nextb->size)) {    // merge with next block, link to free_list
        p->next = nextb->next;
        p->prev = nextb->prev;
        p->next->prev = p;
        p->prev->next = p;
        p->size += nextb->size;
    } else {                    // find next free block in memory, and link
        nextb = (void *) p + p->size;
        while (is_inuse(nextb->size))
            nextb = (void *) nextb + get_size(nextb->size);
        p->prev = nextb->prev;
        p->prev->next = p;
        p->next = nextb;
        nextb->prev = p;
    }
}

void __zfree_null(void);

void zfree(void *ptr) {
    if (!ptr) {
        __zfree_null();
        return;
    }

    struct block_info *p = ptr - sizeof(uintptr_t);

    p->size = set_free(p->size);

    link_to_free_list(p);

    // if previous block is adjacent, merge
    struct block_info *prev = p->prev;
    if ((void *) prev + prev->size == p) {
        prev->next = p->next;
        prev->next->prev = prev;
        prev->size += p->size;
    }
}

void *zrealloc(void *ptr, size_t size) {
    if (!ptr)
        return zmalloc(size);

    if (!size) {
        zfree(ptr);
        return NULL;
    }

    size = size_requirements(size);

    struct block_info *p = ptr - sizeof(uintptr_t);

    if (size > get_size(p->size)) {     // bigger
        void *q = zmalloc(size);
        if (!q) return NULL;
        memcpy(q, ptr, get_size(p->size));
        zfree(ptr);
        return q;
    } else if (get_size(p->size) >= size + minfreeblocksize) { // split
        struct block_info *q = (void *) p + size;
        q->size = get_size(p->size) - size;
        link_to_free_list(q);
        p->size = set_inuse(size);
    }
    return ptr;
}

static void *__zmemalign(uintptr_t alignment, uintptr_t size) {
    if ((alignment & -alignment) != alignment) {
        errno = EINVAL;
        return NULL;
    }
    if (alignment <= sizeof(uintptr_t)) return zmalloc(size);

    uintptr_t worst_padding = sizeof(minfreeblocksize) + \
                              sizeof(uintptr_t) + (alignment - 1);

    if (size > SIZE_MAX - worst_padding) {
        errno = ENOMEM;
        return NULL;
    }

    struct block_info *freeb = zmalloc(size + worst_padding)-sizeof(uintptr_t);
    void *end   = (void *) freeb + get_size(freeb->size);

    // freshly allocated, so prev is still valid (but next is not(!))
    struct block_info *prev = freeb->prev;
    struct block_info *next = prev->next;

    void *tmp = (void *) freeb + minfreeblocksize + sizeof(uintptr_t);
    struct block_info *p = align_up(tmp, alignment) - sizeof(uintptr_t);

    freeb->size = (void *) p - (void *) freeb;

    // insert back into free_list, coalescing is impossible
    prev->next = next->prev = freeb;
    freeb->prev = prev;
    freeb->next = next;

    p->size = set_inuse(end - (void *) p);

    return (void *) p + sizeof(uintptr_t);
}

void *zaligned_alloc(size_t alignment, size_t size) {
    return __zmemalign(alignment, size);
}

int zposix_memalign(void **memptr, size_t alignment, size_t size) {
    if (alignment < sizeof(uintptr_t)) return EINVAL;
    void *mem = __zmemalign(alignment, size);
    if (!mem) return errno;
    *memptr = mem;
    return 0;
}

// ----------------------------------------------------------------------------

#ifdef ZMALLOC_DEBUG
#include <stdio.h>
void print_memory(void) {
    int sentinels = 2;
    unsigned long int total = 0, count = 0;
    struct block_info *p = base, *q;

    printf("Traversing whole memory pool:\n");

    while (sentinels) {
        if (!p->size) {
            printf("Sentinel found\n");
            sentinels--;
            p = (void *) p + sizeof(struct block_info);
            total += sizeof(struct block_info);
        } else {
            printf("Block %ld: size = %ld, %s\n", count++, get_size(p->size),
                                        is_inuse(p->size) ? "used" : "free");
            total += get_size(p->size);
            p = (void *) p + get_size(p->size);
        }
    }

    printf("TOTAL: %ld\n", total);
    puts("--------------------------------");

    printf("Traversing free_list forward:\n");
    count = 0;
    for (p = free_list; p; q = p, p = p->next)
        printf("Block %ld: size = %ld\n", count++, p->size);

    printf("traversing free_list backwards:\n");
    for (p = q; p; p = p->prev)
        printf("block %ld: size = %ld\n", --count, p->size);

    puts("################################");
}
#endif
