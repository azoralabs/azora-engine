/*
 * Azora Engine — FFI plumbing shim.
 *
 * This file contains NO platform logic. The entire platform layer (Cocoa
 * windowing, Metal rendering, CoreText, input) is written in the Azora
 * language (engine/az_objc.az, engine/az_platform_macos.az) and talks to the
 * OS directly through `bridge C` declarations.
 *
 * What lives here is only what a C-ABI FFI cannot express by itself:
 *
 *  1. objc_msgSend trampolines for signatures involving doubles or by-value
 *     structs. On arm64, float/struct arguments travel in v-registers, so
 *     objc_msgSend must be cast to the exact function type at the call site —
 *     that cast is a C-language construct, hence these thin wrappers.
 *     (Integer/pointer-only shapes are called directly from Azora.)
 *
 *  2. Raw-memory helpers (alloc/peek/poke/copy) so Azora can build native
 *     buffers (vertex data, out-parameters) without a C compiler.
 *
 *  3. dlsym access for exported constants (e.g. NSDefaultRunLoopMode).
 */

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef __APPLE__
#include <objc/message.h>
#include <objc/runtime.h>
#endif

typedef struct { double a, b, c, d; } AzQuad;   /* CGRect / MTLClearColor */
typedef struct { double x, y; } AzPair;         /* CGPoint / CGSize */

#ifdef __APPLE__

/* ── objc_msgSend trampolines (double / struct shapes) ─────────────────── */

double az_send_d0(int64_t obj, int64_t sel) {
    return ((double (*)(id, SEL))objc_msgSend)((id)obj, (SEL)sel);
}

double az_send_float0(int64_t obj, int64_t sel) {
    return (double)((float (*)(id, SEL))objc_msgSend)((id)obj, (SEL)sel);
}

int64_t az_send_float1(int64_t obj, int64_t sel, double a) {
    ((void (*)(id, SEL, float))objc_msgSend)((id)obj, (SEL)sel, (float)a);
    return 0;
}

int64_t az_send_f1(int64_t obj, int64_t sel, double a) {
    return (int64_t)((id (*)(id, SEL, double))objc_msgSend)((id)obj, (SEL)sel, a);
}

int64_t az_send_f2(int64_t obj, int64_t sel, double a, double b) {
    return (int64_t)((id (*)(id, SEL, double, double))objc_msgSend)((id)obj, (SEL)sel, a, b);
}

/* 4-double by-value argument (CGRect, MTLClearColor). */
int64_t az_send_quad(int64_t obj, int64_t sel, double a, double b, double c, double d) {
    AzQuad q = { a, b, c, d };
    return (int64_t)((id (*)(id, SEL, AzQuad))objc_msgSend)((id)obj, (SEL)sel, q);
}

/* CGRect + 3 integer arguments (initWithContentRect:styleMask:backing:defer:). */
int64_t az_send_quad_i3(int64_t obj, int64_t sel,
                        double a, double b, double c, double d,
                        int64_t i1, int64_t i2, int64_t i3) {
    AzQuad q = { a, b, c, d };
    return (int64_t)((id (*)(id, SEL, AzQuad, long, long, long))objc_msgSend)(
        (id)obj, (SEL)sel, q, (long)i1, (long)i2, (long)i3);
}

/* 2-double by-value argument (CGSize/CGPoint, e.g. setDrawableSize:). */
int64_t az_send_pair(int64_t obj, int64_t sel, double x, double y) {
    AzPair p = { x, y };
    return (int64_t)((id (*)(id, SEL, AzPair))objc_msgSend)((id)obj, (SEL)sel, p);
}

/* 4-double by-value return (CGRect: bounds/frame).
 * arm64 returns 4-double HFAs in v0–v3; x86_64 returns 32-byte structs in
 * memory and must dispatch through objc_msgSend_stret. */
#if defined(__x86_64__)
extern void objc_msgSend_stret(void);
#define AZ_MSGSEND_QUADRET ((AzQuad (*)(id, SEL))objc_msgSend_stret)
#else
#define AZ_MSGSEND_QUADRET ((AzQuad (*)(id, SEL))objc_msgSend)
#endif

void az_send_out_quad(int64_t obj, int64_t sel, int64_t out4 /* double[4] */) {
    AzQuad q = AZ_MSGSEND_QUADRET((id)obj, (SEL)sel);
    double* o = (double*)out4;
    o[0] = q.a; o[1] = q.b; o[2] = q.c; o[3] = q.d;
}

/* 2-double by-value return (CGPoint/CGSize: mouseLocation…, size). */
void az_send_out_pair(int64_t obj, int64_t sel, int64_t out2 /* double[2] */) {
    AzPair p = ((AzPair (*)(id, SEL))objc_msgSend)((id)obj, (SEL)sel);
    double* o = (double*)out2;
    o[0] = p.x; o[1] = p.y;
}

/* MTLRegion (6 longs, 48 bytes — passed indirectly on arm64) + mip/bytes/rowbytes:
 * replaceRegion:mipmapLevel:withBytes:bytesPerRow:. */
typedef struct { long x, y, z, w, h, d; } AzRegion;
int64_t az_send_region(int64_t obj, int64_t sel,
                       int64_t x, int64_t y, int64_t z,
                       int64_t w, int64_t h, int64_t d,
                       int64_t mip, int64_t bytes, int64_t bytesPerRow) {
    AzRegion r = { (long)x, (long)y, (long)z, (long)w, (long)h, (long)d };
    return (int64_t)((id (*)(id, SEL, AzRegion, long, const void*, long))objc_msgSend)(
        (id)obj, (SEL)sel, r, (long)mip, (const void*)bytes, (long)bytesPerRow);
}

/* getBytes:bytesPerRow:fromRegion:mipmapLevel: (texture readback). */
void az_get_region(int64_t obj, int64_t sel,
                   int64_t bytes, int64_t bytesPerRow,
                   int64_t x, int64_t y, int64_t z,
                   int64_t w, int64_t h, int64_t d,
                   int64_t mip) {
    AzRegion r = { (long)x, (long)y, (long)z, (long)w, (long)h, (long)d };
    ((void (*)(id, SEL, void*, long, AzRegion, long))objc_msgSend)(
        (id)obj, (SEL)sel, (void*)bytes, (long)bytesPerRow, r, (long)mip);
}

#endif /* __APPLE__ */

/* ── Raw memory ────────────────────────────────────────────────────────── */

int64_t az_alloc(int64_t n)              { return (int64_t)calloc(1, (size_t)n); }
void    az_free(int64_t p)               { free((void*)p); }
void    az_copy(int64_t dst, int64_t src, int64_t n) { memcpy((void*)dst, (void*)src, (size_t)n); }

int64_t az_peek64(int64_t p, int64_t off) { return *(int64_t*)((char*)p + off); }
int32_t az_peek32(int64_t p, int64_t off) { return *(int32_t*)((char*)p + off); }
int32_t az_peek8(int64_t p, int64_t off)  { return *(uint8_t*)((char*)p + off); }
double  az_peek_f64(int64_t p, int64_t off) { return *(double*)((char*)p + off); }

void az_poke64(int64_t p, int64_t off, int64_t v)  { *(int64_t*)((char*)p + off) = v; }
void az_poke32(int64_t p, int64_t off, int32_t v)  { *(int32_t*)((char*)p + off) = v; }
void az_poke8(int64_t p, int64_t off, int32_t v)   { *(uint8_t*)((char*)p + off) = (uint8_t)v; }
void az_poke_f32(int64_t p, int64_t off, double v) { *(float*)((char*)p + off) = (float)v; }
void az_poke_f64(int64_t p, int64_t off, double v) { *(double*)((char*)p + off) = v; }

/* ── Exported symbols / constants ──────────────────────────────────────── */

int64_t az_sym(const char* name) { return (int64_t)dlsym(RTLD_DEFAULT, name); }
