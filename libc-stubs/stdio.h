#ifndef _STDIO_H
#define _STDIO_H
typedef struct FILE FILE;
#define NULL ((void*)0)
typedef unsigned long size_t;
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define stderr ((FILE*)0)
#define stdout ((FILE*)0)
#define stdin  ((FILE*)0)
static inline int fprintf(FILE *f, const char *fmt, ...) { (void)f; (void)fmt; return 0; }
static inline int printf(const char *fmt, ...) { (void)fmt; return 0; }
static inline int snprintf(char *buf, size_t n, const char *fmt, ...) { (void)buf; (void)n; (void)fmt; if(n>0) buf[0]=0; return 0; }
static inline int vsnprintf(char *buf, size_t n, const char *fmt, void *ap) { (void)buf; (void)n; (void)fmt; (void)ap; if(n>0) buf[0]=0; return 0; }
static inline int fputs(const char *s, FILE *f) { (void)s; (void)f; return 0; }
static inline int fflush(FILE *f) { (void)f; return 0; }
#endif
