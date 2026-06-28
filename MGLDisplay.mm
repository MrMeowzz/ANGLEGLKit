//
// Copyright 2019 Le Hoang Quyen. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//

#import "MGLDisplay.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglext_angle.h>
#include <EGL/eglplatform.h>
#include <dlfcn.h>

#ifndef EGL_PLATFORM_ANGLE_ANGLE
#define EGL_PLATFORM_ANGLE_ANGLE 0x3202
#endif

#ifndef EGL_PLATFORM_ANGLE_TYPE_ANGLE
#define EGL_PLATFORM_ANGLE_TYPE_ANGLE 0x3203
#endif

#ifndef EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE
#define EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE 0x3489
#endif

#ifndef EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE
#define EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE 0x3209
#endif

#ifndef EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE
#define EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE 0x320A
#endif

namespace
{
typedef __eglMustCastToProperFunctionPointerType (*MGLGetProcAddressProc)(const char *procname);
typedef EGLDisplay (*MGLGetDisplayProc)(EGLNativeDisplayType display_id);
typedef EGLBoolean (*MGLInitializeProc)(EGLDisplay dpy, EGLint *major, EGLint *minor);
typedef EGLint (*MGLGetErrorProc)(void);
typedef EGLBoolean (*MGLTerminateProc)(EGLDisplay dpy);

static void *gLibEGLHandle = nullptr;
static void *gLibGLESHandle = nullptr;
static MGLGetProcAddressProc gGetProcAddress = nullptr;
static MGLGetDisplayProc gGetDisplay = nullptr;
static MGLInitializeProc gInitialize = nullptr;
static MGLGetErrorProc gGetError = nullptr;
static MGLTerminateProc gTerminate = nullptr;

void Throw(NSString *msg)
{
    [NSException raise:@"MGLSurfaceException" format:@"%@", msg];
}

static void *OpenFirstAvailableLibrary(const char *const paths[])
{
    for (int i = 0; paths[i] != nullptr; i++)
    {
        void *handle = dlopen(paths[i], RTLD_NOW | RTLD_GLOBAL);
        if (handle)
        {
            NSLog(@"[ANGLEGLKit] Opened %s", paths[i]);
            return handle;
        }
    }

    NSLog(@"[ANGLEGLKit] dlopen failed. Last dlerror: %s", dlerror());
    return nullptr;
}

static void EnsureEGLLibrariesLoaded()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *eglPaths[] = {
            "@loader_path/../libEGL.framework/libEGL",
            "@rpath/libEGL.framework/libEGL",
            "@executable_path/Frameworks/libEGL.framework/libEGL",
            "libEGL.framework/libEGL",
            nullptr
        };

        const char *glesPaths[] = {
            "@loader_path/../libGLESv2.framework/libGLESv2",
            "@rpath/libGLESv2.framework/libGLESv2",
            "@executable_path/Frameworks/libGLESv2.framework/libGLESv2",
            "libGLESv2.framework/libGLESv2",
            nullptr
        };

        gLibEGLHandle = OpenFirstAvailableLibrary(eglPaths);
        gLibGLESHandle = OpenFirstAvailableLibrary(glesPaths);

        void *eglLookupHandle = gLibEGLHandle ? gLibEGLHandle : RTLD_DEFAULT;
        gGetProcAddress = (MGLGetProcAddressProc)dlsym(eglLookupHandle, "eglGetProcAddress");
        gGetDisplay = (MGLGetDisplayProc)dlsym(eglLookupHandle, "eglGetDisplay");
        gInitialize = (MGLInitializeProc)dlsym(eglLookupHandle, "eglInitialize");
        gGetError = (MGLGetErrorProc)dlsym(eglLookupHandle, "eglGetError");
        gTerminate = (MGLTerminateProc)dlsym(eglLookupHandle, "eglTerminate");

        NSLog(@"[ANGLEGLKit] EGL symbols: eglGetProcAddress=%p eglGetDisplay=%p eglInitialize=%p eglGetError=%p eglTerminate=%p",
              gGetProcAddress, gGetDisplay, gInitialize, gGetError, gTerminate);
    });
}

static void *ResolveEGLProc(const char *name)
{
    EnsureEGLLibrariesLoaded();

    void *proc = nullptr;
    if (gGetProcAddress)
    {
        proc = (void *)gGetProcAddress(name);
    }

    if (!proc && gLibEGLHandle)
    {
        proc = dlsym(gLibEGLHandle, name);
    }

    if (!proc)
    {
        proc = dlsym(RTLD_DEFAULT, name);
    }

    return proc;
}

static void LogEGLError(NSString *prefix)
{
    EnsureEGLLibrariesLoaded();
    if (gGetError)
    {
        EGLint error = gGetError();
        NSLog(@"[ANGLEGLKit] %@ EGL error: 0x%04x", prefix, error);
    }
    else
    {
        NSLog(@"[ANGLEGLKit] %@ EGL error unavailable because eglGetError is missing.", prefix);
    }
}

static EGLDisplay CreateMetalANGLEDisplay()
{
    EnsureEGLLibrariesLoaded();

    EGLDisplay display = EGL_NO_DISPLAY;

    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplayEXT =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)ResolveEGLProc("eglGetPlatformDisplayEXT");

    const EGLint extAttribs[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,
        EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
        EGL_NONE
    };

    if (getPlatformDisplayEXT)
    {
        display = getPlatformDisplayEXT(
            EGL_PLATFORM_ANGLE_ANGLE,
            (void *)0,
            extAttribs
        );

        if (display != EGL_NO_DISPLAY)
        {
            NSLog(@"[ANGLEGLKit] Created EGL display using eglGetPlatformDisplayEXT + MetalANGLE.");
            return display;
        }

        LogEGLError(@"eglGetPlatformDisplayEXT failed");
    }
    else
    {
        NSLog(@"[ANGLEGLKit] eglGetPlatformDisplayEXT is missing.");
    }

#if EGL_VERSION_1_5
    const EGLAttrib attribs15[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,
        EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
        EGL_NONE
    };

    PFNEGLGETPLATFORMDISPLAYPROC getPlatformDisplay =
        (PFNEGLGETPLATFORMDISPLAYPROC)ResolveEGLProc("eglGetPlatformDisplay");

    if (getPlatformDisplay)
    {
        display = getPlatformDisplay(
            EGL_PLATFORM_ANGLE_ANGLE,
            (void *)0,
            attribs15
        );

        if (display != EGL_NO_DISPLAY)
        {
            NSLog(@"[ANGLEGLKit] Created EGL display using eglGetPlatformDisplay + MetalANGLE.");
            return display;
        }

        LogEGLError(@"eglGetPlatformDisplay failed");
    }
    else
    {
        NSLog(@"[ANGLEGLKit] eglGetPlatformDisplay is missing.");
    }
#endif

    if (!gGetDisplay)
    {
        NSLog(@"[ANGLEGLKit] eglGetDisplay is missing.");
        return EGL_NO_DISPLAY;
    }

    display = gGetDisplay(EGL_DEFAULT_DISPLAY);

    if (display != EGL_NO_DISPLAY)
    {
        NSLog(@"[ANGLEGLKit] Created EGL display using fallback eglGetDisplay.");
        return display;
    }

    LogEGLError(@"eglGetDisplay failed");
    return EGL_NO_DISPLAY;
}
}

@interface EGLDisplayHolder : NSObject
@property(nonatomic, assign) EGLDisplay eglDisplay;
@end

@implementation EGLDisplayHolder

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _eglDisplay = CreateMetalANGLEDisplay();

        if (_eglDisplay == EGL_NO_DISPLAY)
        {
            Throw(@"Failed to create EGL display");
        }

        EGLint major = 0;
        EGLint minor = 0;

        if (!gInitialize)
        {
            Throw(@"Failed to resolve eglInitialize()");
        }

        if (!gInitialize(_eglDisplay, &major, &minor))
        {
            LogEGLError(@"eglInitialize failed");
            Throw(@"Failed to call eglInitialize()");
        }

        NSLog(@"[ANGLEGLKit] EGL initialized successfully: %d.%d", major, minor);
    }

    return self;
}

- (void)dealloc
{
    if (_eglDisplay != EGL_NO_DISPLAY)
    {
        EnsureEGLLibrariesLoaded();
        if (gTerminate)
        {
            gTerminate(_eglDisplay);
        }
        _eglDisplay = EGL_NO_DISPLAY;
    }
}

@end

static EGLDisplayHolder *gGlobalDisplayHolder = nil;
static MGLDisplay *gDefaultDisplay = nil;

@interface MGLDisplay ()
@end

@implementation MGLDisplay

+ (MGLDisplay *)defaultDisplay
{
    @synchronized(self)
    {
        if (!gDefaultDisplay)
        {
            gDefaultDisplay = [[MGLDisplay alloc] init];
        }

        return gDefaultDisplay;
    }
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        @synchronized([MGLDisplay class])
        {
            if (!gGlobalDisplayHolder)
            {
                gGlobalDisplayHolder = [[EGLDisplayHolder alloc] init];
            }

            _eglDisplay = gGlobalDisplayHolder.eglDisplay;
        }

        if (_eglDisplay == EGL_NO_DISPLAY)
        {
            Throw(@"MGLDisplay received EGL_NO_DISPLAY");
        }
    }

    return self;
}

@end
