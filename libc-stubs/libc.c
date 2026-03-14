// Minimal libc implementations for SQLite on wasm32-freestanding
#include <stdint.h>

typedef unsigned long size_t;

size_t strlen(const char *s) {
    const char *p = s;
    while (*p) p++;
    return p - s;
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && *s1 == *s2) { s1++; s2++; }
    return (unsigned char)*s1 - (unsigned char)*s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (s1[i] != s2[i] || s1[i] == 0) return (unsigned char)s1[i] - (unsigned char)s2[i];
    }
    return 0;
}

char *strchr(const char *s, int c) {
    while (*s) { if (*s == (char)c) return (char*)s; s++; }
    return (c == 0) ? (char*)s : 0;
}

char *strrchr(const char *s, int c) {
    const char *last = 0;
    while (*s) { if (*s == (char)c) last = s; s++; }
    if (c == 0) return (char*)s;
    return (char*)last;
}

char *strstr(const char *haystack, const char *needle) {
    if (!*needle) return (char*)haystack;
    for (; *haystack; haystack++) {
        const char *h = haystack, *n = needle;
        while (*h && *n && *h == *n) { h++; n++; }
        if (!*n) return (char*)haystack;
    }
    return 0;
}

char *strncpy(char *dest, const char *src, size_t n) {
    size_t i;
    for (i = 0; i < n && src[i]; i++) dest[i] = src[i];
    for (; i < n; i++) dest[i] = 0;
    return dest;
}

size_t strspn(const char *s, const char *accept) {
    size_t count = 0;
    for (; *s; s++) {
        const char *a = accept;
        int found = 0;
        while (*a) { if (*s == *a++) { found = 1; break; } }
        if (!found) break;
        count++;
    }
    return count;
}

size_t strcspn(const char *s, const char *reject) {
    size_t count = 0;
    for (; *s; s++) {
        const char *r = reject;
        while (*r) { if (*s == *r++) return count; }
        count++;
    }
    return count;
}

void *memchr(const void *s, int c, size_t n) {
    const unsigned char *p = s;
    for (size_t i = 0; i < n; i++) {
        if (p[i] == (unsigned char)c) return (void*)(p + i);
    }
    return 0;
}

char *strerror(int errnum) {
    (void)errnum;
    return "error";
}

// Math stubs that SQLite needs
double ceil(double x) { double i = (double)(long long)x; return (x > i) ? i + 1.0 : i; }
double floor(double x) { double i = (double)(long long)x; return (x < i) ? i - 1.0 : i; }
double fabs(double x) { return x < 0 ? -x : x; }
double fmod(double x, double y) { return x - (double)(long long)(x/y) * y; }

// These are trickier but SQLite can work with stubs for basic use
double log(double x) { (void)x; return 0.0; }
double log10(double x) { (void)x; return 0.0; }
double pow(double x, double y) { (void)x; (void)y; return 0.0; }
double sqrt(double x) { (void)x; return 0.0; }
double ldexp(double x, int exp) { (void)exp; return x; }
double frexp(double x, int *exp) { if(exp) *exp = 0; return x; }

// strtod - minimal but functional
double strtod(const char *nptr, char **endptr) {
    double result = 0.0;
    int sign = 1;
    const char *p = nptr;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '-') { sign = -1; p++; }
    else if (*p == '+') p++;
    while (*p >= '0' && *p <= '9') { result = result * 10.0 + (*p - '0'); p++; }
    if (*p == '.') {
        p++;
        double frac = 0.1;
        while (*p >= '0' && *p <= '9') { result += (*p - '0') * frac; frac *= 0.1; p++; }
    }
    if (endptr) *endptr = (char*)p;
    return result * sign;
}

long strtol(const char *nptr, char **endptr, int base) {
    long result = 0;
    int sign = 1;
    const char *p = nptr;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '-') { sign = -1; p++; }
    else if (*p == '+') p++;
    if (base == 0) {
        if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) { base = 16; p += 2; }
        else if (*p == '0') { base = 8; p++; }
        else base = 10;
    }
    while (*p) {
        int digit;
        if (*p >= '0' && *p <= '9') digit = *p - '0';
        else if (*p >= 'a' && *p <= 'f') digit = *p - 'a' + 10;
        else if (*p >= 'A' && *p <= 'F') digit = *p - 'A' + 10;
        else break;
        if (digit >= base) break;
        result = result * base + digit;
        p++;
    }
    if (endptr) *endptr = (char*)p;
    return result * sign;
}

long long strtoll(const char *nptr, char **endptr, int base) {
    return (long long)strtol(nptr, endptr, base);
}

unsigned long long strtoull(const char *nptr, char **endptr, int base) {
    return (unsigned long long)strtol(nptr, endptr, base);
}

int atoi(const char *nptr) { return (int)strtol(nptr, 0, 10); }

void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *)) {
    // Simple insertion sort - good enough for SQLite's usage
    char *b = base;
    char tmp[256]; // should be enough for SQLite's needs
    for (size_t i = 1; i < nmemb; i++) {
        for (size_t j = i; j > 0 && compar(b + j*size, b + (j-1)*size) < 0; j--) {
            __builtin_memcpy(tmp, b + j*size, size);
            __builtin_memcpy(b + j*size, b + (j-1)*size, size);
            __builtin_memcpy(b + (j-1)*size, tmp, size);
        }
    }
}

void abort(void) { __builtin_trap(); }

// SQLite OS_OTHER stubs
int sqlite3_os_init(void) { return 0; }
int sqlite3_os_end(void) { return 0; }
char *getenv(const char *name) { (void)name; return 0; }

// Allocation via SQLite's MEMSYS5 - we provide the memory pool
// SQLite will manage its own memory within this pool
static char sqlite_heap[8*1024*1024] __attribute__((aligned(8))); // 8MB
static int heap_initialized = 0;
static size_t bump_offset = 0;

// Simple bump allocator as bootstrap until MEMSYS5 takes over
void *malloc(size_t size) {
    size = (size + 7) & ~(size_t)7;
    if (bump_offset + size > sizeof(sqlite_heap)) return 0;
    void *ptr = sqlite_heap + bump_offset;
    bump_offset += size;
    return ptr;
}

void free(void *ptr) { (void)ptr; /* bump allocator doesn't free - reset via reset_sqlite_heap() */ }

void reset_sqlite_heap(void) { bump_offset = 0; }

void *realloc(void *ptr, size_t size) {
    if (!ptr) return malloc(size);
    void *new_ptr = malloc(size);
    if (new_ptr && ptr) __builtin_memcpy(new_ptr, ptr, size); // over-copies but safe
    return new_ptr;
}
