#ifndef _STDLIB_H
#define _STDLIB_H
typedef unsigned long size_t;
#define NULL ((void*)0)
void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
double strtod(const char *nptr, char **endptr);
long strtol(const char *nptr, char **endptr, int base);
long long strtoll(const char *nptr, char **endptr, int base);
unsigned long long strtoull(const char *nptr, char **endptr, int base);
void qsort(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *));
int atoi(const char *nptr);
void abort(void);
char *getenv(const char *name);
#endif
