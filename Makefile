TARGET := iphone:clang:16.5:15.0
# arm64 only: clang 11 emits the legacy arm64e ABI, which iOS 17 rejects.
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Bordkino BordkinoNavi

COMMON_FILES = $(wildcard Sources/Core/*.m) $(wildcard Sources/Player/*.m) $(wildcard Sources/Phone/*.m) Sources/Car/BKDiagnosticsViewController.m
COMMON_FRAMEWORKS = UIKit CarPlay AVFoundation AVKit CoreMedia CoreVideo QuartzCore JavaScriptCore CoreLocation MediaPlayer WebKit
COMMON_CFLAGS = -fobjc-arc -ISources/Core -ISources/Player -ISources/Phone -ISources/Car -ISources/Navi -Wno-unguarded-availability-new

Bordkino_FILES = $(COMMON_FILES) $(filter-out Sources/Car/BKDiagnosticsViewController.m,$(wildcard Sources/Car/*.m))
Bordkino_FRAMEWORKS = $(COMMON_FRAMEWORKS)
Bordkino_CFLAGS = $(COMMON_CFLAGS) -DBK_VARIANT_STARK=1
Bordkino_CODESIGN_FLAGS = -Sentitlements/bordkino.plist
Bordkino_RESOURCE_DIRS = Resources/Common Resources/Bordkino
Bordkino_RESOURCE_FILES = js/extractor.js

BordkinoNavi_FILES = $(COMMON_FILES) $(wildcard Sources/Navi/*.m)
BordkinoNavi_FRAMEWORKS = $(COMMON_FRAMEWORKS)
BordkinoNavi_CFLAGS = $(COMMON_CFLAGS) -DBK_VARIANT_NAVI=1
BordkinoNavi_CODESIGN_FLAGS = -Sentitlements/bordkino-navi.plist
BordkinoNavi_RESOURCE_DIRS = Resources/Common Resources/BordkinoNavi
BordkinoNavi_RESOURCE_FILES = js/extractor.js

include $(THEOS_MAKE_PATH)/application.mk
