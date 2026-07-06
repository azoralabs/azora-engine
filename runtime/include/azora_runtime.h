/*
 * Azora Engine — FFI plumbing shim ABI (libazora_runtime).
 *
 * The engine's platform layer (Cocoa windowing, Metal rendering, CoreText)
 * is written in the Azora language and calls the OS directly through the
 * Objective-C runtime and C framework APIs. This shim only provides what a
 * C-ABI FFI cannot express by itself; see runtime/src/ffi/az_ffi.c.
 *
 * Azora-side declarations live in engine/az_objc.az.
 */

#ifndef AZORA_RUNTIME_H
#define AZORA_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef __APPLE__
/* objc_msgSend trampolines for signatures involving doubles or by-value
 * structs (arm64 requires the exact C function type at the call site). */
double  az_send_d0(int64_t obj, int64_t sel);
int64_t az_send_f1(int64_t obj, int64_t sel, double a);
int64_t az_send_f2(int64_t obj, int64_t sel, double a, double b);
int64_t az_send_quad(int64_t obj, int64_t sel, double a, double b, double c, double d);
int64_t az_send_quad_i3(int64_t obj, int64_t sel,
                        double a, double b, double c, double d,
                        int64_t i1, int64_t i2, int64_t i3);
int64_t az_send_pair(int64_t obj, int64_t sel, double x, double y);
void    az_send_out_quad(int64_t obj, int64_t sel, int64_t out4 /* double[4] */);
void    az_send_out_pair(int64_t obj, int64_t sel, int64_t out2 /* double[2] */);
int64_t az_send_region(int64_t obj, int64_t sel,
                       int64_t x, int64_t y, int64_t z,
                       int64_t w, int64_t h, int64_t d,
                       int64_t mip, int64_t bytes, int64_t bytesPerRow);
#endif /* __APPLE__ */

/* Raw memory (native buffers, out-parameters). */
int64_t az_alloc(int64_t n);
void    az_free(int64_t p);
void    az_copy(int64_t dst, int64_t src, int64_t n);
int64_t az_peek64(int64_t p, int64_t off);
int32_t az_peek32(int64_t p, int64_t off);
int32_t az_peek8(int64_t p, int64_t off);
double  az_peek_f64(int64_t p, int64_t off);
void    az_poke64(int64_t p, int64_t off, int64_t v);
void    az_poke32(int64_t p, int64_t off, int32_t v);
void    az_poke8(int64_t p, int64_t off, int32_t v);
void    az_poke_f32(int64_t p, int64_t off, double v);
void    az_poke_f64(int64_t p, int64_t off, double v);

/* Exported symbols/constants (dlsym). */
int64_t az_sym(const char* name);

#ifdef __cplusplus
}
#endif

#endif /* AZORA_RUNTIME_H */
