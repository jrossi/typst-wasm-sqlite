#ifndef _TIME_H
#define _TIME_H
typedef long time_t;
struct tm { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; };
static inline time_t time(time_t *t) { if(t) *t = 0; return 0; }
static inline struct tm *gmtime(const time_t *t) { (void)t; static struct tm z = {0}; return &z; }
static inline struct tm *localtime(const time_t *t) { (void)t; static struct tm z = {0}; return &z; }
static inline size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm) { (void)s; (void)max; (void)fmt; (void)tm; if(max>0) s[0]=0; return 0; }
#endif
