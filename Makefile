# Lightroom Spotlight Importer — Makefile (x86_64 Intel Mac)
# Requires Apple SDK + clang (Xcode or CLT). No Xcode GUI.

PRODUCT       := LightroomSpotlightImporter
BUNDLE_NAME   := $(PRODUCT).mdimporter
HOST_APP_NAME := Lightroom Spotlight Importer.app
SRC_DIR       := LightroomSpotlightImporter
BUILD_DIR     := build
BUNDLE        := $(BUILD_DIR)/$(BUNDLE_NAME)
HOST_APP      := $(BUILD_DIR)/$(HOST_APP_NAME)
MACOS_DIR     := $(BUNDLE)/Contents/MacOS
RES_DIR       := $(BUNDLE)/Contents/Resources

ARCHS         ?= x86_64
DEPLOY_TARGET ?= 11.0
SDKROOT       ?= $(shell xcrun --show-sdk-path)
CC            ?= $(shell xcrun -f clang)

CFLAGS := -arch $(ARCHS) \
	-isysroot $(SDKROOT) \
	-mmacosx-version-min=$(DEPLOY_TARGET) \
	-fobjc-arc \
	-fmodules \
	-fvisibility=hidden \
	-Wall -Wextra -Wno-unused-parameter \
	-I$(SRC_DIR)

LDFLAGS := -arch $(ARCHS) \
	-isysroot $(SDKROOT) \
	-mmacosx-version-min=$(DEPLOY_TARGET) \
	-bundle \
	-framework Foundation \
	-framework CoreFoundation \
	-framework CoreServices \
	-lsqlite3

SRCS := \
	$(SRC_DIR)/main.c \
	$(SRC_DIR)/GetMetadataForFile.m \
	$(SRC_DIR)/LSIImporter.m

OBJS := $(patsubst $(SRC_DIR)/%,$(BUILD_DIR)/obj/%.o,$(SRCS))

.PHONY: all clean install package test probe codesign host matrix

all: $(BUNDLE) host codesign

$(BUILD_DIR)/obj/%.o: $(SRC_DIR)/%
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(MACOS_DIR)/$(PRODUCT): $(OBJS)
	@mkdir -p $(MACOS_DIR)
	$(CC) $(LDFLAGS) $^ -o $@

$(BUNDLE)/Contents/Info.plist: $(SRC_DIR)/LightroomSpotlightImporter-Info.plist
	@mkdir -p $(BUNDLE)/Contents
	cp $< $@

$(RES_DIR)/schema.xml: $(SRC_DIR)/schema.xml
	@mkdir -p $(RES_DIR)
	cp $< $@

$(RES_DIR)/schema.strings: $(SRC_DIR)/schema.strings
	@mkdir -p $(RES_DIR)
	cp $< $@

$(RES_DIR)/en.lproj/InfoPlist.strings: $(SRC_DIR)/en.lproj/InfoPlist.strings
	@mkdir -p $(RES_DIR)/en.lproj
	cp $< $@

$(BUNDLE): $(MACOS_DIR)/$(PRODUCT) \
	$(BUNDLE)/Contents/Info.plist \
	$(RES_DIR)/schema.xml \
	$(RES_DIR)/schema.strings \
	$(RES_DIR)/en.lproj/InfoPlist.strings
	@echo "built $@"

# Host app registers UTI claims (lsregister rejects bare mdimporters with -10811).
host: $(BUNDLE)
	@mkdir -p "$(HOST_APP)/Contents/MacOS" \
		"$(HOST_APP)/Contents/Resources" \
		"$(HOST_APP)/Contents/Library/Spotlight"
	$(CC) -arch $(ARCHS) -isysroot $(SDKROOT) -mmacosx-version-min=$(DEPLOY_TARGET) \
		HostApp/main.c -o "$(HOST_APP)/Contents/MacOS/Lightroom Spotlight Importer"
	cp HostApp/Info.plist "$(HOST_APP)/Contents/Info.plist"
	cp HostApp/AppIcon.icns "$(HOST_APP)/Contents/Resources/AppIcon.icns"
	rm -rf "$(HOST_APP)/Contents/Library/Spotlight/$(BUNDLE_NAME)"
	cp -R "$(BUNDLE)" "$(HOST_APP)/Contents/Library/Spotlight/$(BUNDLE_NAME)"
	@echo "built $(HOST_APP)"

codesign: $(BUNDLE) host
	codesign --force --deep --sign - "$(BUNDLE)"
	codesign --force --deep --sign - "$(HOST_APP)"

probe: $(BUILD_DIR)/lsi-probe

$(BUILD_DIR)/lsi-probe: tools/lsi-probe.m $(SRC_DIR)/LSIImporter.m $(SRC_DIR)/LSIImporter.h
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) tools/lsi-probe.m $(SRC_DIR)/LSIImporter.m \
		-framework Foundation -framework CoreServices -lsqlite3 \
		-o $@

install: all
	./scripts/install.sh

package: all
	./scripts/package.sh

test: all probe
	./scripts/test.sh

clean:
	rm -rf $(BUILD_DIR) dist tests/fixtures/sample.lrcat

matrix: all probe
	./scripts/matrix.sh
