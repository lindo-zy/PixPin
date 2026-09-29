ARCHS = arm64 arm64e

TARGET ?= iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PixPinPrefs

PixPinPrefs_FILES = PXRootListController.m \
	PXTestCaptureController.m \
	PXEditorOrderController.m \
	PXEditorButtonEditController.m \
	../Sources/Common/PXConstants.m \
	../Sources/Common/PXPanelAppearance.m \
	../Sources/Common/PXEditorOrder.m \
	../Sources/Common/PXLog.m \
	../Sources/Common/PXRuntimeStatus.m

PixPinPrefs_INSTALL_PATH = /Library/PreferenceBundles
PixPinPrefs_FRAMEWORKS = UIKit CoreGraphics
PixPinPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport
PixPinPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

# theos 子项目只执行 stage:: internal-stage（makefiles/stage.mk），after-stage 仅顶层
# 调用会跑，挂在子项目永不执行，因此版本同步必须并入 internal-stage。
# build.sh 传入本次实际包版本；只修改暂存资源，不回写源码模板。
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp PixPinPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/PixPinPrefs.plist$(ECHO_END)
	$(ECHO_NOTHING)test -n "$(PACKAGE_VERSION)" || { echo "error: PACKAGE_VERSION not set (use build.sh)" >&2; exit 1; }$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleShortVersionString -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/PixPinPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleVersion -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/PixPinPrefs.bundle/Info.plist"$(ECHO_END)
