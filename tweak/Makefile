THEOS_DEVICE_IP ?= localhost
THEOS_DEVICE_PORT ?= 2222

PACKAGE_NAME := com.hogan.iosscreenstream
PACKAGE_VERSION := 1.2.0
PACKAGE_ARCH := iphoneos-arm
PKG_DEBIAN := com.hogan.iosscreenstream

TARGET = iphone:14.5:14.0

include $(THEOS)/makefiles/common.mk

# ===== Tweak (inject into SpringBoard) =====
TWEAK_NAME := iOSScreenStream
iOSScreenStream_CFLAGS := -fobjc-arc -O3 -Wno-unknown-warning-option
iOSScreenStream_CFLAGS += -I$(THEOS_INCLUDE_PATH)/TrollVNC -I./include
iOSScreenStream_FILES := $(wildcard src/*.mm)
iOSScreenStream_LDFLAGS := -undefined dynamic_lookup

# ===== Preference Bundle =====
BUNDLE_NAME := iOSScreenStreamPrefs
iOSScreenStreamPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOSScreenStreamPrefs_CFLAGS := -fobjc-arc -I./include
iOSScreenStreamPrefs_FILES := prefs/ISSPrefsRootListController.mm
iOSScreenStreamPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
iOSScreenStreamPrefs_PRIVATE_FRAMEWORKS = Preferences
iOSScreenStreamPrefs_LDFLAGS = -ObjC
iOSScreenStreamPrefs_BUNDLE_EXTENSION = bundle

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/package.mk

# ===== Install resources to correct locations =====
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/iOSScreenStreamPrefs$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/iOSScreenStreamPrefs/Root.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle$(ECHO_END)
	$(ECHO_NOTHING)rm -rf $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle/Resources$(ECHO_END)
	$(ECHO_NOTHING)rm -f $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle/info.plist$(ECHO_END)
	$(ECHO_NOTHING)cp prefs_bundle_resources/Info.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle/Info.plist$(ECHO_END)
	$(ECHO_NOTHING)cp prefs_bundle_resources/Root.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle/Root.plist$(ECHO_END)
	$(ECHO_NOTHING)cp prefs_bundle_resources/icon@2x.png $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle/icon@2x.png$(ECHO_END)
	$(ECHO_NOTHING)cp prefs_bundle_resources/icon@3x.png $(THEOS_STAGING_DIR)/Library/PreferenceBundles/iOSScreenStreamPrefs.bundle/icon@3x.png$(ECHO_END)
