# Builds CoolBun.dylib on a Mac (or GitHub Actions macos runner).
# No Theos needed.

SDK     = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC      = xcrun --sdk iphoneos clang
OUT     = build/CoolBun.dylib

all: $(OUT)

$(OUT): CoolBun.m
	@mkdir -p build
	$(CC) -arch arm64 -isysroot $(SDK) -miphoneos-version-min=12.0 \
		-dynamiclib -fobjc-arc -Os \
		-framework UIKit -framework QuartzCore -framework Foundation \
		-install_name @executable_path/Frameworks/CoolBun.dylib \
		-o $(OUT) CoolBun.m
	strip -x $(OUT)
	codesign -f -s - $(OUT)

clean:
	rm -rf build
