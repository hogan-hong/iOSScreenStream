THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222
THEOS_MAKE_PATH = $(THEOS)/makefiles

PACKAGE_NAME = com.yourname.iosscreenstream
PACKAGE_VERSION = 1.0.0
PACKAGE_ARCH = iphoneos-arm
PKG_DEBIAN = com.yourname.iosscreenstream

# Include paths
TWEAK_NAME = iOSScreenStream
iOSScreenStream_CFLAGS = -fobjc-arc -O3 -I$(THEOS_INCLUDE_PATH)/TrollVNC -I./include
iOSScreenStream_FILES = $(wildcard src/*.mm)
iOSScreenStream_LDFLAGS = -undefined dynamic_lookup

# Theos standard
include $(THEOS_MAKE_PATH)/package.mk
include $(THEOS_MAKE_PATH)/tweak.mk
