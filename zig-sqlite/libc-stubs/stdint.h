#ifndef _STDINT_H
#define _STDINT_H
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef signed short int16_t;
typedef unsigned short uint16_t;
typedef signed int int32_t;
typedef unsigned int uint32_t;
typedef signed long long int64_t;
typedef unsigned long long uint64_t;
typedef unsigned long uintptr_t;
typedef long intptr_t;
#define INT32_MAX 2147483647
#define INT64_MAX 9223372036854775807LL
#define UINT32_MAX 4294967295U
#define INT32_MIN (-INT32_MAX - 1)
#endif
