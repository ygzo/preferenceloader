# DON'T USE THIS MAKEFILE! IT IS NOT INTENDED FOR UPSTREAM THEOS

TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e

export THEOS_USE_NEW_ABI=1

include $(THEOS)/makefiles/common.mk

ifeq ($(ROOTLESS),1)
export INSTALL_PREFIX = /var/jb
else
export INSTALL_PREFIX = 
endif

LIBRARY_NAME = plprefs
plprefs_FILES = prefs.xm
plprefs_FRAMEWORKS = UIKit
plprefs_LIBRARIES = substrate
plprefs_PRIVATE_FRAMEWORKS = Preferences
plprefs_CFLAGS = -I.
plprefs_COMPATIBILITY_VERSION = 2.2.0
plprefs_LIBRARY_VERSION = $(or $(shell echo "$(THEOS_PACKAGE_BASE_VERSION)" | cut -d'~' -f1),3.0.0)
plprefs_LDFLAGS  = -compatibility_version $($(THEOS_CURRENT_INSTANCE)_COMPATIBILITY_VERSION)
plprefs_LDFLAGS += -current_version $($(THEOS_CURRENT_INSTANCE)_LIBRARY_VERSION)
plprefs_LDFLAGS += -Wl,-rpath,/var/jb/usr/lib -Wl,-rpath,/usr/lib
plprefs_LDFLAGS += -Wl,-not_for_dyld_shared_cache
plprefs_INSTALL_PATH = $(INSTALL_PREFIX)/usr/lib

TWEAK_NAME = PreferenceLoader
PreferenceLoader_FILES = Tweak.xm
PreferenceLoader_FRAMEWORKS = UIKit
PreferenceLoader_PRIVATE_FRAMEWORKS = Preferences
PreferenceLoader_LIBRARIES =
PreferenceLoader_CFLAGS = -I.
PreferenceLoader_LDFLAGS = -L$(THEOS_OBJ_DIR) -Wl,-rpath,/var/jb/usr/lib -Wl,-rpath,/usr/lib
PreferenceLoader_LDFLAGS += $(THEOS_OBJ_DIR)/plprefs.dylib
PreferenceLoader_LDFLAGS += -Wl,-not_for_dyld_shared_cache
ifeq ($(ROOTLESS),1)
PreferenceLoader_INSTALL_PATH = $(INSTALL_PREFIX)/usr/lib/TweakInject
else
PreferenceLoader_INSTALL_PATH = $(INSTALL_PREFIX)/Library/MobileSubstrate/DynamicLibraries
endif

include $(THEOS_MAKE_PATH)/library.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-plprefs-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/usr/include/libprefs$(ECHO_END)
	$(ECHO_NOTHING)cp prefs.h $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/usr/include/libprefs/prefs.h$(ECHO_END)

after-stage::
# Keep tweak plists as text/XML for maximum loader compatibility.
#   $(FAKEROOT) chown -R root:admin $(THEOS_STAGING_DIR)
	@install_name_tool -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate @rpath/CydiaSubstrate.framework/CydiaSubstrate $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/usr/lib/plprefs.dylib 2>/dev/null || true
	@install_name_tool -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate @rpath/CydiaSubstrate.framework/CydiaSubstrate $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/usr/lib/TweakInject/PreferenceLoader.dylib 2>/dev/null || true
	@install_name_tool -add_rpath /var/jb/Library/Frameworks $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/usr/lib/plprefs.dylib 2>/dev/null || true
	@install_name_tool -add_rpath /var/jb/Library/Frameworks $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/usr/lib/TweakInject/PreferenceLoader.dylib 2>/dev/null || true
	@mkdir -p $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/Library/PreferenceBundles $(THEOS_STAGING_DIR)/$(INSTALL_PREFIX)/Library/PreferenceLoader/Preferences
# 	sudo chown -R root:admin $(THEOS_STAGING_DIR)/Library $(THEOS_STAGING_DIR)/usr

after-install::
	install.exec "killall -9 Preferences"
