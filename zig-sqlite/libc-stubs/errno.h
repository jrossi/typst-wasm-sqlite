#ifndef _ERRNO_H
#define _ERRNO_H
static int _errno_val = 0;
#define errno _errno_val
#endif
