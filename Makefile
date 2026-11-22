# Rootless (palera1n / Dopamine). `override` stops a stray env var or command-line value from
# silently producing a rootful package. For a rootful jailbreak build with:  make package ROOTFUL=1
ifneq ($(ROOTFUL),1)
override THEOS_PACKAGE_SCHEME := rootless
export THEOS_PACKAGE_SCHEME
# Belt and braces for build services whose Theos ignores the scheme: also install under /var/jb explicitly.
override THEOS_PACKAGE_INSTALL_PREFIX := /var/jb
export THEOS_PACKAGE_INSTALL_PREFIX
endif

TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StandBy16
StandBy16_FILES = Tweak.x SBYController.m SBYPages.m SBYServices.m SBYTheme.m
StandBy16_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-arc-performSelector-leaks
StandBy16_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreTelephony CoreMotion CoreImage

SUBPROJECTS += StandBy16Preview StandBy16Prefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# Safety net: Theos only moves the staged files under /var/jb while it builds the .deb, so check afterwards.
# If the result is not rootless, delete it so a bad package can never be installed by accident.
ifneq ($(ROOTFUL),1)
after-package::
	@test -d "$(THEOS_STAGING_DIR)/var/jb" || { echo "StandBy16 ERROR: this build is NOT rootless (no var/jb in the package). Removing it. Convert the .deb with the steps in the README instead."; rm -f "$(_THEOS_DEB_PACKAGE_FILENAME)"; exit 1; }
endif
