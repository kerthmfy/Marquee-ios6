TARGET := iphone:clang:11.4:6.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Marquee
Marquee_FILES = $(wildcard Marquee/*.m)
Marquee_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security SystemConfiguration
Marquee_CFLAGS = -fobjc-arc -mno-thumb -Wno-error=deprecated-module-dot-map
Marquee_CODESIGN_FLAGS = -SMarquee/Marquee.entitlements
Marquee_INSTALL_PATH = /Applications
Marquee_RESOURCE_FILES = Marquee/Resources/Info.plist \
	Marquee/Resources/Icon.png \
	Marquee/Resources/Icon@2x.png \
	Marquee/Resources/Icon-72.png \
	Marquee/Resources/Icon-72@2x.png \
	Marquee/Resources/Default.png \
	Marquee/Resources/Default@2x.png \
	Marquee/Resources/Default-568h@2x.png \
	Marquee/Resources/Default-Portrait.png \
	Marquee/Resources/Default-Portrait@2x.png \
	Marquee/Resources/Default-Landscape.png \
	Marquee/Resources/Default-Landscape@2x.png \
	Marquee/Resources/SimklBadge.png

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 Marquee || true"
