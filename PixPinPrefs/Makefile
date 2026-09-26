ARCHS = arm64 arm64e

TARGET ?= iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PixPinPrefs

PixPinPrefs_FILES = PXRootListController.m \
	PXTestCaptureController.m \
	PXURLSchemeCell.m \
	../Sources/Common/PXConstants.m \
	../Sources/Common/PXLog.m \
	../Sources/Common/PXRuntimeStatus.m

PixPinPrefs_INSTALL_PATH = /Library/PreferenceBundles
PixPinPrefs_FRAMEWORKS = UIKit CoreGraphics
PixPinPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport
PixPinPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp PixPinPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/PixPinPrefs.plist$(ECHO_END)
