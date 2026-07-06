/*
 * Azora Engine native runtime — macOS backend (Cocoa + Metal).
 *
 * Implements the C ABI in runtime/include/azora_runtime.h. The window is a
 * plain NSWindow whose content view is backed by a CAMetalLayer; events are
 * pumped manually each frame (game-loop style, no [NSApp run]), and all
 * rendering goes through two Metal pipelines:
 *
 *   - 3D: position+normal vertices, per-draw MVP/model/color, lambert shading
 *   - 2D: position+uv+color vertices in window points, used for UI rects and
 *         text quads (text is rasterized with AppKit into cached textures)
 *
 * Compile: clang -fobjc-arc -dynamiclib azrt_macos.m
 *          -framework Cocoa -framework Metal -framework QuartzCore
 */

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include "../../include/azora_runtime.h"

#include <math.h>
#include <string.h>

/* ── Shaders (compiled from source at init) ────────────────────────────── */

static NSString* const kShaderSource = @""
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"\n"
"struct V3In  { float3 pos [[attribute(0)]]; float3 normal [[attribute(1)]]; };\n"
"struct V3Out { float4 pos [[position]]; float3 normal; };\n"
"struct U3    { float4x4 viewProj; float4x4 model; float4 color; };\n"
"\n"
"vertex V3Out v3_main(uint vid [[vertex_id]],\n"
"                     const device float* verts [[buffer(0)]],\n"
"                     constant U3& u [[buffer(1)]]) {\n"
"    V3Out out;\n"
"    float3 p = float3(verts[vid*6+0], verts[vid*6+1], verts[vid*6+2]);\n"
"    float3 n = float3(verts[vid*6+3], verts[vid*6+4], verts[vid*6+5]);\n"
"    out.pos = u.viewProj * u.model * float4(p, 1.0);\n"
"    out.normal = (u.model * float4(n, 0.0)).xyz;\n"
"    return out;\n"
"}\n"
"\n"
"fragment float4 f3_main(V3Out in [[stage_in]], constant U3& u [[buffer(1)]]) {\n"
"    float3 l = normalize(float3(0.5, 0.8, 0.3));\n"
"    float d = max(dot(normalize(in.normal), l), 0.0);\n"
"    float i = 0.35 + 0.65 * d;\n"
"    return float4(u.color.rgb * i, u.color.a);\n"
"}\n"
"\n"
"struct V2Out { float4 pos [[position]]; float2 uv; float4 color; };\n"
"struct U2    { float2 viewport; float useTex; float pad; };\n"
"\n"
"vertex V2Out v2_main(uint vid [[vertex_id]],\n"
"                     const device float* verts [[buffer(0)]],\n"
"                     constant U2& u [[buffer(1)]]) {\n"
"    V2Out out;\n"
"    float2 p = float2(verts[vid*8+0], verts[vid*8+1]);\n"
"    out.pos = float4(p.x / u.viewport.x * 2.0 - 1.0,\n"
"                     1.0 - p.y / u.viewport.y * 2.0, 0.0, 1.0);\n"
"    out.uv = float2(verts[vid*8+2], verts[vid*8+3]);\n"
"    out.color = float4(verts[vid*8+4], verts[vid*8+5], verts[vid*8+6], verts[vid*8+7]);\n"
"    return out;\n"
"}\n"
"\n"
"fragment float4 f2_main(V2Out in [[stage_in]], constant U2& u [[buffer(1)]],\n"
"                        texture2d<float> tex [[texture(0)]],\n"
"                        sampler smp [[sampler(0)]]) {\n"
"    if (u.useTex > 0.5) {\n"
"        float4 t = tex.sample(smp, in.uv);\n"
"        return float4(in.color.rgb, in.color.a * t.a);\n"
"    }\n"
"    return in.color;\n"
"}\n";

/* ── State ─────────────────────────────────────────────────────────────── */

typedef struct { float m[16]; } Mat4f; /* column-major, GPU-ready */

typedef struct {
    float viewProj[16];
    float model[16];
    float color[4];
} Uniforms3D;

@interface AzWindowDelegate : NSObject <NSWindowDelegate>
@end

@interface AzContentView : NSView
@end

#define AZ_MAX_MESHES 256
#define AZ_MAX_KEYS   1024

static struct {
    NSWindow* window;
    AzWindowDelegate* delegate;
    CAMetalLayer* layer;

    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    id<MTLRenderPipelineState> pipe3d;
    id<MTLRenderPipelineState> pipe2d;
    id<MTLDepthStencilState> depthOn;
    id<MTLDepthStencilState> depthOff;
    id<MTLTexture> depthTex;
    id<MTLSamplerState> sampler;

    id<CAMetalDrawable> drawable;
    id<MTLCommandBuffer> cmd;
    id<MTLRenderCommandEncoder> enc;

    id<MTLBuffer> meshes[AZ_MAX_MESHES];
    uint32_t meshVertexCount[AZ_MAX_MESHES];
    int32_t meshCount;

    NSMutableDictionary<NSString*, id>* textCache;   /* "size|text" → texture */
    NSMutableDictionary<NSString*, NSValue*>* textSize;

    float viewProj[16];
    double clearR, clearG, clearB;

    uint8_t keyDown[AZ_MAX_KEYS];
    uint8_t keyPressed[AZ_MAX_KEYS];
    uint8_t mouseDown[3];
    uint8_t mouseClicked[3];

    double startTime;
    double lastFrameTime;
    double delta;

    int shouldClose;
    int inited;
    int is2dMode;      /* current encoder pipeline, to avoid redundant switches */
    int hasEncoder;
} G;

static double now_seconds(void) {
    return [NSDate timeIntervalSinceReferenceDate];
}

/* ── Window delegate / view ────────────────────────────────────────────── */

@implementation AzWindowDelegate
- (BOOL)windowShouldClose:(NSWindow*)sender { G.shouldClose = 1; return YES; }
@end

@implementation AzContentView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
@end

/* ── Matrix helpers ────────────────────────────────────────────────────── */

/* Converts a row-major double[16] (translation at 3,7,11) to the column-major
 * float[16] Metal expects. */
static void mat_to_gpu(const double* rm, float* out) {
    for (int c = 0; c < 4; c++)
        for (int r = 0; r < 4; r++)
            out[c * 4 + r] = (float)rm[r * 4 + c];
}

/* ── Input mapping ─────────────────────────────────────────────────────── */

static int32_t map_key(NSEvent* ev) {
    switch (ev.keyCode) {
        case 53:  return AZ_KEY_ESCAPE;
        case 36:  return AZ_KEY_ENTER;
        case 48:  return AZ_KEY_TAB;
        case 49:  return AZ_KEY_SPACE;
        case 123: return AZ_KEY_LEFT;
        case 124: return AZ_KEY_RIGHT;
        case 126: return AZ_KEY_UP;
        case 125: return AZ_KEY_DOWN;
        default: break;
    }
    NSString* chars = ev.charactersIgnoringModifiers;
    if (chars.length == 0) return -1;
    unichar c = [chars.uppercaseString characterAtIndex:0];
    if (c < 128) return (int32_t)c;
    return -1;
}

static void set_key(int32_t key, int down) {
    if (key < 0 || key >= AZ_MAX_KEYS) return;
    if (down && !G.keyDown[key]) G.keyPressed[key] = 1;
    G.keyDown[key] = down ? 1 : 0;
}

static void pump_events(void) {
    memset(G.keyPressed, 0, sizeof(G.keyPressed));
    memset(G.mouseClicked, 0, sizeof(G.mouseClicked));

    @autoreleasepool {
        for (;;) {
            NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate distantPast]
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];
            if (!ev) break;
            switch (ev.type) {
                case NSEventTypeKeyDown:
                    if (!ev.isARepeat) set_key(map_key(ev), 1);
                    continue; /* swallow: avoids the system beep for unhandled keys */
                case NSEventTypeKeyUp:
                    set_key(map_key(ev), 0);
                    continue;
                case NSEventTypeFlagsChanged:
                    set_key(AZ_KEY_SHIFT, (ev.modifierFlags & NSEventModifierFlagShift) ? 1 : 0);
                    break;
                case NSEventTypeLeftMouseDown:
                    if (!G.mouseDown[0]) G.mouseClicked[0] = 1;
                    G.mouseDown[0] = 1;
                    break;
                case NSEventTypeLeftMouseUp:    G.mouseDown[0] = 0; break;
                case NSEventTypeRightMouseDown:
                    if (!G.mouseDown[1]) G.mouseClicked[1] = 1;
                    G.mouseDown[1] = 1;
                    break;
                case NSEventTypeRightMouseUp:   G.mouseDown[1] = 0; break;
                default: break;
            }
            [NSApp sendEvent:ev];
        }
    }
}

/* ── Metal setup ───────────────────────────────────────────────────────── */

static int create_pipelines(void) {
    NSError* err = nil;
    id<MTLLibrary> lib = [G.device newLibraryWithSource:kShaderSource options:nil error:&err];
    if (!lib) {
        NSLog(@"azrt: shader compile failed: %@", err);
        return -1;
    }

    MTLRenderPipelineDescriptor* d3 = [MTLRenderPipelineDescriptor new];
    d3.vertexFunction = [lib newFunctionWithName:@"v3_main"];
    d3.fragmentFunction = [lib newFunctionWithName:@"f3_main"];
    d3.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    d3.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    G.pipe3d = [G.device newRenderPipelineStateWithDescriptor:d3 error:&err];
    if (!G.pipe3d) { NSLog(@"azrt: 3d pipeline failed: %@", err); return -1; }

    MTLRenderPipelineDescriptor* d2 = [MTLRenderPipelineDescriptor new];
    d2.vertexFunction = [lib newFunctionWithName:@"v2_main"];
    d2.fragmentFunction = [lib newFunctionWithName:@"f2_main"];
    d2.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    d2.colorAttachments[0].blendingEnabled = YES;
    d2.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    d2.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    d2.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    d2.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    d2.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    G.pipe2d = [G.device newRenderPipelineStateWithDescriptor:d2 error:&err];
    if (!G.pipe2d) { NSLog(@"azrt: 2d pipeline failed: %@", err); return -1; }

    MTLDepthStencilDescriptor* dOn = [MTLDepthStencilDescriptor new];
    dOn.depthCompareFunction = MTLCompareFunctionLess;
    dOn.depthWriteEnabled = YES;
    G.depthOn = [G.device newDepthStencilStateWithDescriptor:dOn];

    MTLDepthStencilDescriptor* dOff = [MTLDepthStencilDescriptor new];
    dOff.depthCompareFunction = MTLCompareFunctionAlways;
    dOff.depthWriteEnabled = NO;
    G.depthOff = [G.device newDepthStencilStateWithDescriptor:dOff];

    MTLSamplerDescriptor* sd = [MTLSamplerDescriptor new];
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    G.sampler = [G.device newSamplerStateWithDescriptor:sd];
    return 0;
}

static void ensure_depth_texture(void) {
    CGSize ds = G.layer.drawableSize;
    if (ds.width < 1 || ds.height < 1) return;
    if (G.depthTex && G.depthTex.width == (NSUInteger)ds.width &&
        G.depthTex.height == (NSUInteger)ds.height) return;
    MTLTextureDescriptor* td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                           width:(NSUInteger)ds.width
                                                          height:(NSUInteger)ds.height
                                                       mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    td.storageMode = MTLStorageModePrivate;
    G.depthTex = [G.device newTextureWithDescriptor:td];
}

static void update_drawable_size(void) {
    NSView* view = G.window.contentView;
    CGFloat scale = G.window.backingScaleFactor;
    CGSize sz = view.bounds.size;
    CGSize target = CGSizeMake(sz.width * scale, sz.height * scale);
    if (!CGSizeEqualToSize(G.layer.drawableSize, target)) {
        G.layer.drawableSize = target;
    }
}

/* ── Lifecycle ─────────────────────────────────────────────────────────── */

int32_t az_init(const char* title, int32_t width, int32_t height) {
    if (G.inited) return 0;
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSRect frame = NSMakeRect(0, 0, width, height);
        NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        G.window = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
        G.window.title = [NSString stringWithUTF8String:title ? title : "Azora"];
        G.delegate = [AzWindowDelegate new];
        G.window.delegate = G.delegate;
        G.window.releasedWhenClosed = NO;
        [G.window center];

        AzContentView* view = [[AzContentView alloc] initWithFrame:frame];
        view.wantsLayer = YES;
        G.window.contentView = view;

        G.device = MTLCreateSystemDefaultDevice();
        if (!G.device) { NSLog(@"azrt: no Metal device"); return -1; }
        G.queue = [G.device newCommandQueue];

        G.layer = [CAMetalLayer layer];
        G.layer.device = G.device;
        G.layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        G.layer.contentsScale = G.window.backingScaleFactor;
        view.layer = G.layer;
        update_drawable_size();

        if (create_pipelines() != 0) return -1;

        G.textCache = [NSMutableDictionary new];
        G.textSize = [NSMutableDictionary new];
        G.meshCount = 0;
        G.clearR = 0.10; G.clearG = 0.10; G.clearB = 0.12;

        /* Identity view-projection until the app sets a camera. */
        memset(G.viewProj, 0, sizeof(G.viewProj));
        G.viewProj[0] = G.viewProj[5] = G.viewProj[10] = G.viewProj[15] = 1.0f;

        [G.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp finishLaunching];

        G.startTime = now_seconds();
        G.lastFrameTime = G.startTime;
        G.delta = 1.0 / 60.0;
        G.shouldClose = 0;
        G.inited = 1;
    }
    return 0;
}

int32_t az_frame_begin(void) {
    if (!G.inited) return 0;
    pump_events();
    if (G.shouldClose) return 0;

    double t = now_seconds();
    G.delta = t - G.lastFrameTime;
    if (G.delta > 0.25) G.delta = 0.25; /* clamp hitches (debugger pauses etc.) */
    G.lastFrameTime = t;

    @autoreleasepool {
        update_drawable_size();
        ensure_depth_texture();

        G.drawable = [G.layer nextDrawable];
        if (!G.drawable) { G.hasEncoder = 0; return 1; } /* skip drawing this frame */

        G.cmd = [G.queue commandBuffer];
        MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = G.drawable.texture;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor =
            MTLClearColorMake(G.clearR, G.clearG, G.clearB, 1.0);
        rp.depthAttachment.texture = G.depthTex;
        rp.depthAttachment.loadAction = MTLLoadActionClear;
        rp.depthAttachment.storeAction = MTLStoreActionDontCare;
        rp.depthAttachment.clearDepth = 1.0;

        G.enc = [G.cmd renderCommandEncoderWithDescriptor:rp];
        G.hasEncoder = 1;
        G.is2dMode = -1; /* force pipeline set on first draw */
    }
    return 1;
}

void az_frame_end(void) {
    if (!G.inited || !G.hasEncoder) return;
    @autoreleasepool {
        [G.enc endEncoding];
        [G.cmd presentDrawable:G.drawable];
        [G.cmd commit];
        G.enc = nil;
        G.cmd = nil;
        G.drawable = nil;
        G.hasEncoder = 0;
    }
}

void az_shutdown(void) {
    if (!G.inited) return;
    @autoreleasepool {
        [G.window close];
        G.window = nil;
        G.layer = nil;
        for (int i = 0; i < G.meshCount; i++) G.meshes[i] = nil;
        G.textCache = nil;
        G.textSize = nil;
        G.inited = 0;
    }
}

void az_request_close(void) { G.shouldClose = 1; }

/* ── Timing / window ───────────────────────────────────────────────────── */

double az_time(void)  { return now_seconds() - G.startTime; }
double az_delta(void) { return G.delta; }

int32_t az_window_width(void)  {
    return G.inited ? (int32_t)G.window.contentView.bounds.size.width : 0;
}
int32_t az_window_height(void) {
    return G.inited ? (int32_t)G.window.contentView.bounds.size.height : 0;
}

void az_set_clear_color(double r, double g, double b) {
    G.clearR = r; G.clearG = g; G.clearB = b;
}

/* ── Input ─────────────────────────────────────────────────────────────── */

int32_t az_key_down(int32_t key) {
    return (key >= 0 && key < AZ_MAX_KEYS) ? G.keyDown[key] : 0;
}
int32_t az_key_pressed(int32_t key) {
    return (key >= 0 && key < AZ_MAX_KEYS) ? G.keyPressed[key] : 0;
}

double az_mouse_x(void) {
    if (!G.inited) return 0;
    NSPoint p = [G.window mouseLocationOutsideOfEventStream];
    return p.x;
}
double az_mouse_y(void) {
    if (!G.inited) return 0;
    NSPoint p = [G.window mouseLocationOutsideOfEventStream];
    return G.window.contentView.bounds.size.height - p.y; /* flip to top-left origin */
}
int32_t az_mouse_down(int32_t b)    { return (b >= 0 && b < 3) ? G.mouseDown[b] : 0; }
int32_t az_mouse_clicked(int32_t b) { return (b >= 0 && b < 3) ? G.mouseClicked[b] : 0; }

/* ── 3D rendering ──────────────────────────────────────────────────────── */

void az_camera_set(const double* m16) {
    if (m16) mat_to_gpu(m16, G.viewProj);
}

static int32_t register_mesh(const float* verts, uint32_t vertexCount) {
    if (G.meshCount >= AZ_MAX_MESHES) return 0;
    id<MTLBuffer> buf = [G.device newBufferWithBytes:verts
                                              length:vertexCount * 6 * sizeof(float)
                                             options:MTLResourceStorageModeShared];
    if (!buf) return 0;
    G.meshes[G.meshCount] = buf;
    G.meshVertexCount[G.meshCount] = vertexCount;
    G.meshCount++;
    return G.meshCount; /* handles are 1-based */
}

int32_t az_mesh_cube(double size) {
    const float h = (float)(size * 0.5);
    /* 6 faces × 2 triangles × 3 vertices, position + normal interleaved. */
    const float f[6][3] = {
        { 0,  0,  1}, { 0,  0, -1}, {-1,  0,  0}, { 1,  0,  0}, { 0,  1,  0}, { 0, -1,  0}
    };
    float verts[36 * 6];
    int vi = 0;
    for (int face = 0; face < 6; face++) {
        const float* n = f[face];
        /* Build the face basis: normal n, tangent t, bitangent b. */
        float t[3], b[3];
        if (fabsf(n[1]) > 0.5f) { t[0] = 1; t[1] = 0; t[2] = 0; }
        else                    { t[0] = 0; t[1] = 1; t[2] = 0; }
        /* b = n × t, then t = b × n for orthogonality */
        b[0] = n[1]*t[2] - n[2]*t[1];
        b[1] = n[2]*t[0] - n[0]*t[2];
        b[2] = n[0]*t[1] - n[1]*t[0];
        t[0] = b[1]*n[2] - b[2]*n[1];
        t[1] = b[2]*n[0] - b[0]*n[2];
        t[2] = b[0]*n[1] - b[1]*n[0];

        /* Quad corners in (t, b) space, counter-clockwise seen from outside. */
        const float corners[6][2] = {
            {-1, -1}, {1, -1}, {1, 1},
            {-1, -1}, {1, 1}, {-1, 1}
        };
        for (int c = 0; c < 6; c++) {
            float u = corners[c][0], v = corners[c][1];
            verts[vi++] = (n[0] + t[0]*u + b[0]*v) * h;
            verts[vi++] = (n[1] + t[1]*u + b[1]*v) * h;
            verts[vi++] = (n[2] + t[2]*u + b[2]*v) * h;
            verts[vi++] = n[0];
            verts[vi++] = n[1];
            verts[vi++] = n[2];
        }
    }
    return register_mesh(verts, 36);
}

int32_t az_mesh_grid(double extent, int32_t divisions) {
    if (divisions < 1) divisions = 1;
    if (divisions > 64) divisions = 64;
    int quads = divisions * divisions;
    uint32_t vertexCount = (uint32_t)(quads * 6);
    float* verts = malloc(vertexCount * 6 * sizeof(float));
    if (!verts) return 0;
    float step = (float)(2.0 * extent / divisions);
    float x0 = (float)-extent, z0 = (float)-extent;
    int vi = 0;
    for (int i = 0; i < divisions; i++) {
        for (int j = 0; j < divisions; j++) {
            float xa = x0 + i * step, xb = xa + step;
            float za = z0 + j * step, zb = za + step;
            const float quad[6][2] = {
                {xa, za}, {xb, za}, {xb, zb},
                {xa, za}, {xb, zb}, {xa, zb}
            };
            for (int c = 0; c < 6; c++) {
                verts[vi++] = quad[c][0];
                verts[vi++] = 0.0f;
                verts[vi++] = quad[c][1];
                verts[vi++] = 0.0f;
                verts[vi++] = 1.0f;
                verts[vi++] = 0.0f;
            }
        }
    }
    int32_t handle = register_mesh(verts, vertexCount);
    free(verts);
    return handle;
}

static void set_pipeline_3d(void) {
    if (G.is2dMode != 0) {
        [G.enc setRenderPipelineState:G.pipe3d];
        [G.enc setDepthStencilState:G.depthOn];
        G.is2dMode = 0;
    }
}

void az_mesh_draw(int32_t mesh, const double* model16, double r, double g, double b) {
    if (!G.hasEncoder || mesh < 1 || mesh > G.meshCount || !model16) return;
    set_pipeline_3d();

    Uniforms3D u;
    memcpy(u.viewProj, G.viewProj, sizeof(u.viewProj));
    mat_to_gpu(model16, u.model);
    u.color[0] = (float)r; u.color[1] = (float)g; u.color[2] = (float)b; u.color[3] = 1.0f;

    [G.enc setVertexBuffer:G.meshes[mesh - 1] offset:0 atIndex:0];
    [G.enc setVertexBytes:&u length:sizeof(u) atIndex:1];
    [G.enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
    [G.enc drawPrimitives:MTLPrimitiveTypeTriangle
              vertexStart:0
              vertexCount:G.meshVertexCount[mesh - 1]];
}

/* ── 2D / UI rendering ─────────────────────────────────────────────────── */

typedef struct { float viewport[2]; float useTex; float pad; } Uniforms2D;

/* Draws 6 vertices (pos.xy, uv, rgba) with the 2D pipeline. Coordinates are
 * window points; the shader maps them to NDC using the drawable size, so we
 * pre-multiply by the backing scale here. */
static void draw_quad_2d(float x, float y, float w, float h,
                         float u0, float v0, float u1, float v1,
                         float r, float g, float b, float a,
                         id<MTLTexture> tex) {
    if (!G.hasEncoder) return;
    if (G.is2dMode != 1) {
        [G.enc setRenderPipelineState:G.pipe2d];
        [G.enc setDepthStencilState:G.depthOff];
        G.is2dMode = 1;
    }
    float s = (float)G.window.backingScaleFactor;
    float x0 = x * s, y0 = y * s, x1 = (x + w) * s, y1 = (y + h) * s;
    float verts[6][8] = {
        {x0, y0, u0, v0, r, g, b, a},
        {x1, y0, u1, v0, r, g, b, a},
        {x1, y1, u1, v1, r, g, b, a},
        {x0, y0, u0, v0, r, g, b, a},
        {x1, y1, u1, v1, r, g, b, a},
        {x0, y1, u0, v1, r, g, b, a},
    };
    Uniforms2D u;
    CGSize ds = G.layer.drawableSize;
    u.viewport[0] = (float)ds.width;
    u.viewport[1] = (float)ds.height;
    u.useTex = tex ? 1.0f : 0.0f;
    u.pad = 0;

    [G.enc setVertexBytes:verts length:sizeof(verts) atIndex:0];
    [G.enc setVertexBytes:&u length:sizeof(u) atIndex:1];
    [G.enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
    [G.enc setFragmentSamplerState:G.sampler atIndex:0];
    if (tex) [G.enc setFragmentTexture:tex atIndex:0];
    [G.enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

void az_ui_rect(double x, double y, double w, double h,
                double r, double g, double b, double a) {
    draw_quad_2d((float)x, (float)y, (float)w, (float)h,
                 0, 0, 1, 1, (float)r, (float)g, (float)b, (float)a, nil);
}

/* Rasterizes `text` at font `size` into a cached white-on-transparent texture. */
static id<MTLTexture> text_texture(NSString* text, double size, CGSize* outPoints) {
    NSString* key = [NSString stringWithFormat:@"%.1f|%@", size, text];
    id<MTLTexture> cached = G.textCache[key];
    if (cached) {
        *outPoints = [G.textSize[key] sizeValue];
        return cached;
    }

    NSFont* font = [NSFont systemFontOfSize:(CGFloat)size];
    NSDictionary* attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSAttributedString* as = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    NSSize pts = as.size;
    if (pts.width < 1) pts.width = 1;
    if (pts.height < 1) pts.height = 1;

    CGFloat scale = G.window.backingScaleFactor;
    NSInteger pw = (NSInteger)ceil(pts.width * scale);
    NSInteger ph = (NSInteger)ceil(pts.height * scale);

    NSBitmapImageRep* rep =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                pixelsWide:pw
                                                pixelsHigh:ph
                                             bitsPerSample:8
                                           samplesPerPixel:4
                                                  hasAlpha:YES
                                                  isPlanar:NO
                                            colorSpaceName:NSDeviceRGBColorSpace
                                               bytesPerRow:pw * 4
                                              bitsPerPixel:32];
    if (!rep) return nil;

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext* ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext setCurrentContext:ctx];
    NSAffineTransform* xform = [NSAffineTransform transform];
    [xform scaleBy:scale];
    [xform concat];
    [as drawAtPoint:NSZeroPoint];
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    MTLTextureDescriptor* td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:pw
                                                          height:ph
                                                       mipmapped:NO];
    id<MTLTexture> tex = [G.device newTextureWithDescriptor:td];
    if (!tex) return nil;
    [tex replaceRegion:MTLRegionMake2D(0, 0, pw, ph)
           mipmapLevel:0
             withBytes:rep.bitmapData
           bytesPerRow:(NSUInteger)pw * 4];

    G.textCache[key] = tex;
    G.textSize[key] = [NSValue valueWithSize:pts];
    /* Unbounded caches leak in long sessions with dynamic strings; keep it simple. */
    if (G.textCache.count > 512) {
        [G.textCache removeAllObjects];
        [G.textSize removeAllObjects];
        G.textCache[key] = tex;
        G.textSize[key] = [NSValue valueWithSize:pts];
    }
    *outPoints = pts;
    return tex;
}

void az_ui_text(const char* text, double x, double y, double size,
                double r, double g, double b) {
    if (!text || !G.inited) return;
    @autoreleasepool {
        NSString* s = [NSString stringWithUTF8String:text];
        if (!s || s.length == 0) return;
        CGSize pts;
        id<MTLTexture> tex = text_texture(s, size, &pts);
        if (!tex) return;
        /* NSBitmapImageRep memory is top-row-first, matching the quad's
         * top-left-origin UVs — no vertical flip needed. */
        draw_quad_2d((float)x, (float)y, (float)pts.width, (float)pts.height,
                     0, 0, 1, 1, (float)r, (float)g, (float)b, 1.0f, tex);
    }
}

double az_ui_text_width(const char* text, double size) {
    if (!text) return 0;
    @autoreleasepool {
        NSString* s = [NSString stringWithUTF8String:text];
        if (!s) return 0;
        NSFont* font = [NSFont systemFontOfSize:(CGFloat)size];
        NSAttributedString* as =
            [[NSAttributedString alloc] initWithString:s
                                            attributes:@{NSFontAttributeName: font}];
        return as.size.width;
    }
}

double az_ui_text_height(double size) {
    @autoreleasepool {
        NSFont* font = [NSFont systemFontOfSize:(CGFloat)size];
        NSAttributedString* as =
            [[NSAttributedString alloc] initWithString:@"Ag"
                                            attributes:@{NSFontAttributeName: font}];
        return as.size.height;
    }
}

/* ── Diagnostics ───────────────────────────────────────────────────────── */

const char* az_backend_name(void) { return "Metal"; }
