THEOS_DEVICE_IP ?= localhost
THEOS_DEVICE_PORT ?= 2222

PACKAGE_NAME := com.hogan.iosscreenstream
PACKAGE_VERSION := 1.1.0
PACKAGE_ARCH := iphoneos-arm
PKG_DEBIAN := com.hogan.iosscreenstream

TARGET = iphone:14.5

include $(THEOS)/makefiles/common.mk

# ===== Tweak（注入 SpringBoard 的 dylib）=====
TWEAK_NAME := iOSScreenStream
iOSScreenStream_CFLAGS := -fobjc-arc -O3 -Wno-unknown-warning-option
iOSScreenStream_CFLAGS += -I$(THEOS_INCLUDE_PATH)/TrollVNC -I./include
iOSScreenStream_FILES := $(wildcard src/*.mm)
iOSScreenStream_LDFLAGS := -undefined dynamic_lookup

# ===== 偏好设置 Bundle =====
BUNDLE_NAME := iOSScreenStreamPrefs
iOSScreenStreamPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOSScreenStreamPrefs_CFLAGS := -fobjc-arc
iOSScreenStreamPrefs_FILES := prefs/ISSPrefsRootListController.mm
iOSScreenStreamPrefs_LDFLAGS := -undefined dynamic_lookup
iOSScreenStreamPrefs_LDFLAGS += -framework Foundation -framework UIKit -framework CoreFoundation
iOSScreenStreamPrefs_BUNDLE_EXTENSION = bundle

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/package.mk

# ===== 将 entry.plist 安装到 PreferenceLoader 目录 =====
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/iOSScreenStream.plist$(ECHO_END)

