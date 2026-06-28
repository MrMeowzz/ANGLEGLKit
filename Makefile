export THEOS=./theos

ARCHS = arm64
TARGET = iphone:clang:latest:11.0
FINALPACKAGE = 1
FOR_RELEASE = 1
IGNORE_WARNING = 0
MOBILE_THEOS = 1

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = ANGLEGLKit

ANGLEGLKit_FILES = \
	MGLContext.mm \
	MGLDisplay.mm \
	MGLKView.mm \
	MGLKViewController.mm \
	MGLLayer.mm \
	MGLKit.m

ANGLEGLKit_PUBLIC_HEADERS = include/

ANGLEGLKit_CFLAGS = \
	-fobjc-arc \
	-fno-modules \
	-Iinclude \
	-IFrameworks/libEGL.framework/Headers \
	-IFrameworks/libGLESv2.framework/Headers \
	-DGL_GLEXT_PROTOTYPES \
	-DGLES_SILENCE_DEPRECATION

ANGLEGLKit_CCFLAGS = \
	-std=c++11 \
	-fno-modules \
	-Iinclude \
	-IFrameworks/libEGL.framework/Headers \
	-IFrameworks/libGLESv2.framework/Headers

ANGLEGLKit_OBJCCFLAGS = \
	-std=c++11 \
	-fno-modules \
	-Iinclude \
	-IFrameworks/libEGL.framework/Headers \
	-IFrameworks/libGLESv2.framework/Headers

ANGLEGLKit_FRAMEWORKS = \
	Foundation \
	UIKit \
	QuartzCore \
	CoreGraphics

ANGLEGLKit_LDFLAGS = \
	-FFrameworks \
	-framework libEGL \
	-framework libGLESv2 \
	-Wl,-needed_framework,libEGL \
	-Wl,-needed_framework,libGLESv2 \
	-Wl,-reexport_framework,libGLESv2 \
	-Wl,-rpath,@loader_path/../ \
	-Wl,-rpath,@executable_path/Frameworks

include $(THEOS_MAKE_PATH)/framework.mk