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

namespace
{
void Throw(NSString *msg)
{
    [NSException raise:@"MGLSurfaceException" format:@"%@", msg];
}

static void LogEGLError(NSString *prefix)
{
    EGLint error = eglGetError();
    NSLog(@"[ANGLEGLKit] %@ EGL error: 0x%04x", prefix, error);
}

static EGLDisplay CreateMetalANGLEDisplay()
{
    EGLDisplay display = EGL_NO_DISPLAY;

    const EGLint metalAttribs[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE,
        EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,

        EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE,
        EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,

        EGL_NONE,
    };

    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplayEXT =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");

    if (getPlatformDisplayEXT)
    {
        display = getPlatformDisplayEXT(
            EGL_PLATFORM_ANGLE_ANGLE,
            EGL_DEFAULT_DISPLAY,
            metalAttribs
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
    display = eglGetPlatformDisplay(
        EGL_PLATFORM_ANGLE_ANGLE,
        EGL_DEFAULT_DISPLAY,
        (const EGLAttrib *)metalAttribs
    );

    if (display != EGL_NO_DISPLAY)
    {
        NSLog(@"[ANGLEGLKit] Created EGL display using eglGetPlatformDisplay + MetalANGLE.");
        return display;
    }

    LogEGLError(@"eglGetPlatformDisplay failed");
#endif

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);

    if (display != EGL_NO_DISPLAY)
    {
        NSLog(@"[ANGLEGLKit] Created EGL display using fallback eglGetDisplay.");
        return display;
    }

    LogEGLError(@"eglGetDisplay failed");
    return EGL_NO_DISPLAY;
}
}

// EGLDisplayHolder
@interface EGLDisplayHolder : NSObject
@property(nonatomic) EGLDisplay eglDisplay;
@end

@implementation EGLDisplayHolder

- (id)init
{
    if (self = [super init])
    {
        _eglDisplay = CreateMetalANGLEDisplay();

        if (_eglDisplay == EGL_NO_DISPLAY)
        {
            Throw(@"Failed to create EGL display");
        }

        EGLint major = 0;
        EGLint minor = 0;

        if (!eglInitialize(_eglDisplay, &major, &minor))
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
        eglTerminate(_eglDisplay);
        _eglDisplay = EGL_NO_DISPLAY;
    }
}

@end

static EGLDisplayHolder *gGlobalDisplayHolder;
static MGLDisplay *gDefaultDisplay;

// MGLDisplay implementation
@interface MGLDisplay () {
    EGLDisplayHolder *_eglDisplayHolder;
}

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

- (id)init
{
    if (self = [super init])
    {
        @synchronized([MGLDisplay class])
        {
            if (!gGlobalDisplayHolder)
            {
                gGlobalDisplayHolder = [[EGLDisplayHolder alloc] init];
            }

            _eglDisplayHolder = gGlobalDisplayHolder;
            _eglDisplay = _eglDisplayHolder.eglDisplay;
        }

        if (_eglDisplay == EGL_NO_DISPLAY)
        {
            Throw(@"MGLDisplay received EGL_NO_DISPLAY");
        }
    }

    return self;
}

@end