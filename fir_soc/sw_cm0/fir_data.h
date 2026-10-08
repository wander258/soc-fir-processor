/* 由 build.py 自动生成，勿手改 */
#ifndef FIR_DATA_H
#define FIR_DATA_H
#include <stdint.h>
#define NTAP 9
#define NSAMP 8
static const int16_t h[NTAP] = {
  -134, 252, 2925, 7973, 10735, 7973, 2925, 252, -134
};
static const int16_t x[NSAMP] = {
  32767, 0, 0, 0, 0, 0, 0, 0
};
#endif
