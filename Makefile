SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path)
CFLAGS = -fobjc-arc -fmodules -Wall -Wextra -mmacosx-version-min=11.0 -isysroot $(SDKROOT)
FRAMEWORKS = -framework AppKit -framework Foundation -framework CoreMIDI

all:
	clang $(CFLAGS) -fsyntax-only Strip3/main.m Strip3/KeyboardConfiguration.m Strip3/MidiOutput.m Strip3/KeyboardTouchBarView.m Strip3/KeyboardTouchBarController.m Strip3/AbletonAccessibility.m Strip3/AbletonRecordControl.m $(FRAMEWORKS) -framework ApplicationServices

build:
	mkdir -p build/Strip3£.app/Contents/MacOS
	cp Strip3/Info.plist build/Strip3£.app/Contents/Info.plist
	clang -fobjc-arc -fmodules -Wall -Wextra -mmacosx-version-min=11.0 -isysroot $(SDKROOT) Strip3/main.m Strip3/KeyboardConfiguration.m Strip3/MidiOutput.m Strip3/KeyboardTouchBarView.m Strip3/KeyboardTouchBarController.m Strip3/AbletonAccessibility.m Strip3/AbletonRecordControl.m $(FRAMEWORKS) -framework ApplicationServices -o build/Strip3£.app/Contents/MacOS/Strip3£
	codesign --force --sign - build/Strip3£.app

test:
	clang $(CFLAGS) Tests/KeyboardConfigurationTest.m Strip3/KeyboardConfiguration.m -framework Foundation -o /tmp/strip3-keyboard-config-test
	/tmp/strip3-keyboard-config-test
	clang $(CFLAGS) Tests/KeyboardTouchBarControllerTest.m Strip3/KeyboardConfiguration.m Strip3/MidiOutput.m Strip3/KeyboardTouchBarView.m Strip3/KeyboardTouchBarController.m Strip3/AbletonAccessibility.m Strip3/AbletonRecordControl.m $(FRAMEWORKS) -framework ApplicationServices -o /tmp/strip3-touchbar-structure-test
	/tmp/strip3-touchbar-structure-test
	clang $(CFLAGS) Tests/AbletonRecordControlTest.m Strip3/AbletonRecordControl.m -framework AppKit -framework Foundation -o /tmp/strip3-record-gesture-test
	/tmp/strip3-record-gesture-test

clean:
	true
