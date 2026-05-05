THEOS_DEVICE_IP ?= localhost
THEOS_DEVICE_PORT ?= 2222

PACKAGE_NAME := com.hogan.iosscreenstream
PACKAGE_VERSION := 1.1.0
PACKAGE_ARCH := iphoneos-arm
PKG_DEBIAN := com.hogan.iosscreenstream

TARGET = iphone:14.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := iOSScreenStream
iOSScreenStream_CFLAGS := -fobjc-arc -O3 -Wno-unknown-warning-option
iOSScreenStream_CFLAGS += -I$(THEOS_INCLUDE_PATH)/TrollVNC -I./include
iOSScreenStream_FILES := $(wildcard src/*.mm)
iOSScreenStream_LDFLAGS := -undefined dynamic_lookup

include $(THEOS)/makefiles/package.mk
include $(THEOS)/makefiles/tweak.mk
