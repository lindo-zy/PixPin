export ARCHS = arm64 arm64e

# 默认值与 build.sh 保持一致；build.sh 按 iOS 16 / iOS 17 双目标覆盖 TARGET。
TARGET ?= iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide
export TARGET THEOS_PACKAGE_SCHEME

export DEBUG = 0
export FINALPACKAGE = 1

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PixPin

PixPin_FILES = $(wildcard Sources/Common/*.m) \
	$(wildcard Sources/Capture/*.m) \
	$(wildcard Sources/Overlay/*.m) \
	$(wildcard Sources/Editor/*.m) \
	$(wildcard Sources/Output/*.m) \
	$(wildcard Sources/History/*.m) \
	$(wildcard Sources/SpringBoard/*.xm)

PixPin_CFLAGS = -fobjc-arc
PixPin_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreText Photos ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += PixPinPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
