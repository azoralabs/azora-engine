/*
 * Azora Engine native runtime — stub backend.
 *
 * Placeholder implementation of the azora_runtime.h ABI for platforms where
 * the real renderer is not implemented yet (the Vulkan backend for
 * Windows/Linux is planned). Every entry point is safe to call; az_init
 * reports failure so apps exit cleanly with a clear message.
 */

#include "../../include/azora_runtime.h"
#include <stdio.h>

int32_t az_init(const char* title, int32_t width, int32_t height) {
    (void)title; (void)width; (void)height;
    fprintf(stderr,
            "azora-engine: no native renderer for this platform yet "
            "(Vulkan backend planned; macOS/Metal is currently supported).\n");
    return -1;
}

int32_t az_frame_begin(void) { return 0; }
void az_frame_end(void) {}
void az_shutdown(void) {}
void az_request_close(void) {}

double az_time(void) { return 0; }
double az_delta(void) { return 0; }
int32_t az_window_width(void) { return 0; }
int32_t az_window_height(void) { return 0; }
void az_set_clear_color(double r, double g, double b) { (void)r; (void)g; (void)b; }

int32_t az_key_down(int32_t key) { (void)key; return 0; }
int32_t az_key_pressed(int32_t key) { (void)key; return 0; }
double az_mouse_x(void) { return 0; }
double az_mouse_y(void) { return 0; }
int32_t az_mouse_down(int32_t button) { (void)button; return 0; }
int32_t az_mouse_clicked(int32_t button) { (void)button; return 0; }

void az_camera_set(const double* view_proj16) { (void)view_proj16; }
int32_t az_mesh_cube(double size) { (void)size; return 0; }
int32_t az_mesh_grid(double extent, int32_t divisions) { (void)extent; (void)divisions; return 0; }
void az_mesh_draw(int32_t mesh, const double* model16, double r, double g, double b) {
    (void)mesh; (void)model16; (void)r; (void)g; (void)b;
}

void az_ui_rect(double x, double y, double w, double h,
                double r, double g, double b, double a) {
    (void)x; (void)y; (void)w; (void)h; (void)r; (void)g; (void)b; (void)a;
}
void az_ui_text(const char* text, double x, double y, double size,
                double r, double g, double b) {
    (void)text; (void)x; (void)y; (void)size; (void)r; (void)g; (void)b;
}
double az_ui_text_width(const char* text, double size) { (void)text; (void)size; return 0; }
double az_ui_text_height(double size) { (void)size; return 0; }

const char* az_backend_name(void) { return "Stub"; }
