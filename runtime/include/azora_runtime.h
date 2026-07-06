/*
 * Azora Engine — native platform runtime ("azrt")
 *
 * C ABI consumed by Azora-language engine code through `bridge C { ... }`
 * declarations. The ABI deliberately uses only int32_t / int64_t / double /
 * const char* so every signature maps 1:1 onto Azora's Int / Long / Real /
 * String types (matrix parameters are passed as a pointer to 16 doubles,
 * which is exactly the memory layout of the engine's `Mat4` pack).
 *
 * Backends:
 *   - macOS:  Cocoa window + Metal renderer (runtime/src/macos/azrt_macos.m)
 *   - other:  Vulkan backend planned; stub reports "unsupported" for now
 *             (runtime/src/stub/azrt_stub.c)
 *
 * Threading: all functions must be called from the main thread.
 */

#ifndef AZORA_RUNTIME_H
#define AZORA_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Lifecycle ─────────────────────────────────────────────────────────── */

/** Creates the window and GPU device. Returns 0 on success, non-zero on failure. */
int32_t az_init(const char* title, int32_t width, int32_t height);

/**
 * Starts a frame: pumps native events, updates input/frame timing, acquires
 * the next drawable and begins the render pass.
 * Returns 1 while the app should keep running, 0 once the window was closed.
 */
int32_t az_frame_begin(void);

/** Ends the frame: submits GPU work and presents the drawable. */
void az_frame_end(void);

/** Destroys the window and GPU resources. */
void az_shutdown(void);

/** Requests app exit: the next az_frame_begin returns 0 (e.g. a Quit button). */
void az_request_close(void);

/* ── Timing / window ───────────────────────────────────────────────────── */

/** Seconds elapsed since az_init. */
double az_time(void);

/** Seconds elapsed between the two most recent az_frame_begin calls. */
double az_delta(void);

int32_t az_window_width(void);   /* logical points */
int32_t az_window_height(void);  /* logical points */

/** Background clear color for subsequent frames (components 0..1). */
void az_set_clear_color(double r, double g, double b);

/* ── Input ─────────────────────────────────────────────────────────────── */
/*
 * Key codes: printable keys use their uppercase ASCII code ('W' == 87).
 * Special keys use the AZ_KEY_* constants below.
 */

enum {
    AZ_KEY_ESCAPE = 27,
    AZ_KEY_ENTER  = 13,
    AZ_KEY_TAB    = 9,
    AZ_KEY_SPACE  = 32,
    AZ_KEY_LEFT   = 1001,
    AZ_KEY_RIGHT  = 1002,
    AZ_KEY_UP     = 1003,
    AZ_KEY_DOWN   = 1004,
    AZ_KEY_SHIFT  = 1005,
};

int32_t az_key_down(int32_t key);      /* 1 while held */
int32_t az_key_pressed(int32_t key);   /* 1 only on the frame the key went down */
double  az_mouse_x(void);              /* window points, origin top-left */
double  az_mouse_y(void);
int32_t az_mouse_down(int32_t button);     /* 0 = left, 1 = right */
int32_t az_mouse_clicked(int32_t button);  /* 1 only on the frame the button went down */

/* ── 3D rendering ──────────────────────────────────────────────────────── */
/*
 * Matrices are row-major double[16] with translation in elements 3, 7, 11
 * (the layout of the engine's Mat4 pack). The runtime converts to the GPU's
 * native layout internally.
 */

/** Sets the view-projection matrix used by subsequent az_mesh_draw calls. */
void az_camera_set(const double* view_proj16);

/** Creates a unit-cube mesh scaled by `size`. Returns a mesh handle (>= 1), 0 on failure. */
int32_t az_mesh_cube(double size);

/** Creates a flat grid mesh in the XZ plane (`extent` half-size, `divisions` cells per side). */
int32_t az_mesh_grid(double extent, int32_t divisions);

/** Draws a mesh with a model matrix and a base color (simple lambert shading). */
void az_mesh_draw(int32_t mesh, const double* model16, double r, double g, double b);

/* ── 2D / UI rendering (drawn after 3D, same frame) ────────────────────── */
/* Coordinates are window points with the origin at the top-left corner.    */

void az_ui_rect(double x, double y, double w, double h,
                double r, double g, double b, double a);

void az_ui_text(const char* text, double x, double y, double size,
                double r, double g, double b);

/** Measured width in points of `text` at font `size` (for centering labels). */
double az_ui_text_width(const char* text, double size);

/** Measured line height in points of font `size`. */
double az_ui_text_height(double size);

/* ── Diagnostics ───────────────────────────────────────────────────────── */

/** Renderer backend name, e.g. "Metal" or "Stub". */
const char* az_backend_name(void);

#ifdef __cplusplus
}
#endif

#endif /* AZORA_RUNTIME_H */
