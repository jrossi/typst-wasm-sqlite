#ifndef _MATH_H
#define _MATH_H
double ceil(double x);
double floor(double x);
double fabs(double x);
double log(double x);
double log10(double x);
double pow(double x, double y);
double sqrt(double x);
double fmod(double x, double y);
double ldexp(double x, int exp);
double frexp(double x, int *exp);
#define INFINITY (__builtin_inf())
#define NAN (__builtin_nan(""))
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#endif
