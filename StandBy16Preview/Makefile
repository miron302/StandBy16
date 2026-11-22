# Rootless (palera1n / Dopamine). `override` stops a stray env var or command-line value from
# silently producing a rootful package. For a rootful jailbreak build with:  make package ROOTFUL=1
ifneq ($(ROOTFUL),1)
override THEOS_PACKAGE_SCHEME := rootless
export THEOS_PACKAGE_SCHEME
endif

TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = StandBy16Preview
StandBy16Preview_FILES = main.m ../SBYPages.m ../SBYTheme.m ../SBYServices.m
StandBy16Preview_FRAMEWORKS = UIKit CoreGraphics QuartzCore
StandBy16Preview_CFLAGS = -fobjc-arc -I.. -Wno-deprecated-declarations -Wno-unused-variable -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/application.mk
