TARGET := iphone:clang:11.4:6.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Marquee
Marquee_FILES = $(wildcard Marquee/*.m)
Marquee_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security SystemConfiguration
Marquee_CFLAGS = -fobjc-arc -mno-thumb -Wno-error=deprecated-module-dot-map
Marquee_CODESIGN_FLAGS = -S
Marquee_INSTALL_PATH = /Applications
Marquee_RESOURCE_FILES = Marquee/Resources/Info.plist

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 Marquee || true"
