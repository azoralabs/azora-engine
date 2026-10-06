/*
 * Copyright 2026 AzoraLabs
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#ifdef __APPLE__
#include <objc/message.h>
#include <objc/runtime.h>
#endif

typedef struct { double a, b, c, d; } AzQuad;   /* CGRect / MTLClearColor */
typedef struct { double x, y; } AzPair;         /* CGPoint / CGSize */

/*
 * Native implementations for the bridge declarations in std.math. Azora
 * preserves the library zone in emitted symbols, so these adapters expose the
 * corresponding C math functions under that stable ABI.
 */
double __std_math_sin(double x)              { return sin(x); }
double __std_math_cos(double x)              { return cos(x); }
double __std_math_tan(double x)              { return tan(x); }
double __std_math_asin(double x)             { return asin(x); }
double __std_math_acos(double x)             { return acos(x); }
double __std_math_atan(double x)             { return atan(x); }
double __std_math_atan2(double y, double x)   { return atan2(y, x); }
double __std_math_sqrt(double x)              { return sqrt(x); }
double __std_math_cbrt(double x)              { return cbrt(x); }
double __std_math_log(double x)               { return log(x); }
double __std_math_log2(double x)              { return log2(x); }
double __std_math_log10(double x)             { return log10(x); }
double __std_math_exp(double x)               { return exp(x); }
double __std_math_exp2(double x)              { return exp2(x); }
double __std_math_hypot(double x, double y)    { return hypot(x, y); }

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

/* setScissorRect: — MTLScissorRect is four NSUIntegers by value, which a
 * C-ABI FFI cannot express, so it is built here and passed as one struct.
 * Metal validates the rectangle against the drawable, so the caller must
 * clamp it: an out-of-bounds scissor aborts the process rather than clipping. */
typedef struct { unsigned long x, y, width, height; } AzScissor;
void az_send_scissor(int64_t obj, int64_t sel,
                     int64_t x, int64_t y, int64_t w, int64_t h) {
    AzScissor r = { (unsigned long)x, (unsigned long)y,
                    (unsigned long)w, (unsigned long)h };
    ((void (*)(id, SEL, AzScissor))objc_msgSend)((id)obj, (SEL)sel, r);
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
/* A NUL-terminated byte run inside a raw block, read as an Azora String. The
 * String aliases the block: it is valid until the block is rewritten. */
const char* az_cstring(int64_t p, int64_t off) { return (const char*)p + off; }

/* ── Process-wide close request ────────────────────────────────────────── */
/*
 * Azora has no mutable global: a top-level `var` is rejected as unsafe to
 * share, and `fin` is deeply immutable, so its contents cannot stand in for
 * one either. That is a deliberate language rule, not a gap to work around
 * in Azora source — which makes this one bit exactly the kind of thing that
 * belongs here, alongside the other constructs the language cannot express.
 *
 * It is one bit, written from any thread and read by the frame loop, so it is
 * atomic with relaxed ordering: the loop only needs to observe the request
 * eventually, and nothing else is published through it.
 */
static _Atomic int az_close_requested = 0;

void    az_request_exit(void)   { __c11_atomic_store(&az_close_requested, 1, __ATOMIC_RELAXED); }
int64_t az_exit_requested(void) { return __c11_atomic_load(&az_close_requested, __ATOMIC_RELAXED); }

/* ── Text cache ────────────────────────────────────────────────────────── */
/*
 * Rasterising a string is the most expensive thing a frame does: a CoreText
 * line, a bitmap and a GPU texture. Interface text rarely changes between
 * frames, so each (font, pixel size, text) is rasterised once and its texture
 * kept until it goes unused for a while. The table holds opaque handles only;
 * creating and releasing textures stays in Azora with the rest of the
 * platform layer. Like the close request, this is process state the language
 * deliberately cannot hold in a global, which is why it lives here.
 */
#define AZ_TEXT_BUCKETS 4096
typedef struct AzTextEntry {
    struct AzTextEntry* next;
    char* key;
    int64_t texture;
    double width, ascent, descent;
    int64_t frame;
} AzTextEntry;
static AzTextEntry* az_text_buckets[AZ_TEXT_BUCKETS];
static AzTextEntry* az_text_hit;
static int64_t az_text_frame;
static char* az_text_scratch;
static size_t az_text_scratch_size;

static const char* az_text_key(const char* font, double size, const char* text, uint64_t* hash) {
    size_t need = strlen(font) + strlen(text) + 40;
    if (need > az_text_scratch_size) {
        char* grown = realloc(az_text_scratch, need);
        if (!grown) return NULL;
        az_text_scratch = grown;
        az_text_scratch_size = need;
    }
    snprintf(az_text_scratch, az_text_scratch_size, "%s\x1f%.3f\x1f%s", font, size, text);
    uint64_t h = 1469598103934665603ull;
    for (const unsigned char* c = (const unsigned char*)az_text_scratch; *c; c++) { h ^= *c; h *= 1099511628211ull; }
    *hash = h;
    return az_text_scratch;
}

/* 1 when the entry exists (and is now the current hit), else 0. */
int64_t az_text_cache_find(const char* font, double size, const char* text) {
    uint64_t hash;
    const char* key = az_text_key(font, size, text, &hash);
    if (!key) return 0;
    for (AzTextEntry* e = az_text_buckets[hash % AZ_TEXT_BUCKETS]; e; e = e->next) {
        if (strcmp(e->key, key) == 0) { e->frame = az_text_frame; az_text_hit = e; return 1; }
    }
    return 0;
}
int64_t az_text_cache_texture(void) { return az_text_hit ? az_text_hit->texture : 0; }
double  az_text_cache_width(void)   { return az_text_hit ? az_text_hit->width : 0.0; }
double  az_text_cache_ascent(void)  { return az_text_hit ? az_text_hit->ascent : 0.0; }
double  az_text_cache_descent(void) { return az_text_hit ? az_text_hit->descent : 0.0; }

/* Records metrics, and a texture when one exists (0 for a measurement only).
 * An existing entry keeps its texture unless a new one is given. */
void az_text_cache_store(const char* font, double size, const char* text,
                         int64_t texture, double width, double ascent, double descent) {
    if (az_text_cache_find(font, size, text)) {
        if (texture) az_text_hit->texture = texture;
        az_text_hit->width = width; az_text_hit->ascent = ascent; az_text_hit->descent = descent;
        return;
    }
    uint64_t hash;
    const char* key = az_text_key(font, size, text, &hash);
    AzTextEntry* e = key ? calloc(1, sizeof(AzTextEntry)) : NULL;
    if (!e) return;
    e->key = strdup(key);
    if (!e->key) { free(e); return; }
    e->texture = texture; e->width = width; e->ascent = ascent; e->descent = descent;
    e->frame = az_text_frame;
    e->next = az_text_buckets[hash % AZ_TEXT_BUCKETS];
    az_text_buckets[hash % AZ_TEXT_BUCKETS] = e;
    az_text_hit = e;
}

/* Starts a frame: entries touched from here on count as used by it. */
void az_text_cache_advance(void) { az_text_frame++; }

/* Removes one entry unused for more than [age] frames and answers its texture
 * (0 when it had none) for the caller to release; -1 when none is that old. */
int64_t az_text_cache_evict(int64_t age) {
    for (int b = 0; b < AZ_TEXT_BUCKETS; b++) {
        for (AzTextEntry** link = &az_text_buckets[b]; *link; link = &(*link)->next) {
            AzTextEntry* e = *link;
            if (az_text_frame - e->frame > age) {
                int64_t texture = e->texture;
                *link = e->next;
                if (az_text_hit == e) az_text_hit = NULL;
                free(e->key);
                free(e);
                return texture;
            }
        }
    }
    return -1;
}

/* ── Exported symbols / constants ──────────────────────────────────────── */

int64_t az_sym(const char* name) { return (int64_t)dlsym(RTLD_DEFAULT, name); }
