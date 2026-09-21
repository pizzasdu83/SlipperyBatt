TARGET := iphone:15.6:15.0
ARCHS = arm64e arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SlipperyBatt
SlipperyBatt_FILES = Tweak.xm
SlipperyBatt_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

BUNDLE_NAME = SlipperyBattPrefs
SlipperyBattPrefs_FILES = SBTPrefsListController.m
SlipperyBattPrefs_INSTALL_PATH = /Library/PreferenceBundles
SlipperyBattPrefs_FRAMEWORKS = UIKit
SlipperyBattPrefs_PRIVATE_FRAMEWORKS = Preferences
SlipperyBattPrefs_LDFLAGS = -ObjC
SlipperyBattPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
