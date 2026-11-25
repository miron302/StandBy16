# Rootless (palera1n / Dopamine). `override` stops a stray env var or command-line value from
# silently producing a rootful package. For a rootful jailbreak build with:  make package ROOTFUL=1
ifneq ($(ROOTFUL),1)
override THEOS_PACKAGE_SCHEME := rootless
export THEOS_PACKAGE_SCHEME
endif

TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = StandBy16Prefs
StandBy16Prefs_FILES = SBYPrefControllers.m
StandBy16Prefs_INSTALL_PATH = /Library/PreferenceBundles
StandBy16Prefs_FRAMEWORKS = UIKit
StandBy16Prefs_CFLAGS = -fobjc-arc
# PSListController & friends are private; Settings has them loaded already, so resolve them at load time.
StandBy16Prefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
