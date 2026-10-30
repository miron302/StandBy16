# Rootless (palera1n default on iOS 16). For a rootful jailbreak, delete the next line.
export THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StandBy16
StandBy16_FILES = Tweak.x SBYController.m SBYPages.m SBYServices.m SBYTheme.m
StandBy16_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-arc-performSelector-leaks
StandBy16_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreTelephony CoreMotion CoreImage

include $(THEOS_MAKE_PATH)/tweak.mk
