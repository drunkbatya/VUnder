PROJECT        := VUnder.xcodeproj
SCHEME         := VUnder
BUNDLE_ID      := com.drunkbatya.VUnder
CONFIGURATION  ?= Release
BUILD_DIR      := build
GENERATED_DIR  := generated
ARCHIVE        := $(BUILD_DIR)/$(SCHEME).xcarchive
EXPORT_DIR     := $(BUILD_DIR)/ipa
IPA            := $(EXPORT_DIR)/$(SCHEME).ipa
EXPORT_OPTIONS := $(GENERATED_DIR)/ExportOptions.plist
VERSION        ?= $(shell git describe --tags --exact-match --match '[0-9]*' 2>/dev/null || echo 0.0.0)
BUILD_NUMBER   ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

-include local.mk

TEAM_ID        ?=
SIGNING_STYLE  ?= automatic
EXPORT_METHOD  ?= development
PROFILE_NAME   ?=
SIGNING_IDENTITY ?= Apple Distribution
DEVICE         ?=
SIMULATOR      ?= iPhone 15

export TEAM_ID EXPORT_METHOD PROFILE_NAME BUNDLE_ID

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION)
VERSION_FLAGS := MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

ifeq ($(SIGNING_STYLE),automatic)
SIGNING_FLAGS := -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(TEAM_ID)
else
SIGNING_FLAGS := CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=$(TEAM_ID) PROVISIONING_PROFILE_SPECIFIER="$(PROFILE_NAME)" CODE_SIGN_IDENTITY="$(SIGNING_IDENTITY)"
endif

.PHONY: all resolve build simulator archive ipa install clean version

all: ipa

resolve:
	xcodebuild -resolvePackageDependencies -project $(PROJECT) -scheme $(SCHEME)

build:
	$(XCODEBUILD) -destination 'generic/platform=iOS' -derivedDataPath $(BUILD_DIR)/DerivedData $(SIGNING_FLAGS) build

simulator:
	$(XCODEBUILD) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' -derivedDataPath $(BUILD_DIR)/DerivedData CODE_SIGNING_ALLOWED=NO build

archive: check-team
	$(XCODEBUILD) -destination 'generic/platform=iOS' -archivePath $(ARCHIVE) $(SIGNING_FLAGS) $(VERSION_FLAGS) archive

version:
	@echo "$(VERSION) ($(BUILD_NUMBER))"

$(EXPORT_OPTIONS): templates/ExportOptions.$(SIGNING_STYLE).plist.in scripts/render_template.py
	mkdir -p $(GENERATED_DIR)
	python3 scripts/render_template.py $< TEAM_ID EXPORT_METHOD PROFILE_NAME BUNDLE_ID > $@

ipa: archive $(EXPORT_OPTIONS)
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist $(EXPORT_OPTIONS) -exportPath $(EXPORT_DIR) $(if $(filter automatic,$(SIGNING_STYLE)),-allowProvisioningUpdates)
	@ls -la $(EXPORT_DIR)/*.ipa

install: check-device
	xcrun devicectl device install app --device $(DEVICE) $(IPA)

check-team:
	@test -n "$(TEAM_ID)" || { echo "TEAM_ID is empty (set it in local.mk or on the command line)"; exit 1; }

check-device:
	@test -n "$(DEVICE)" || { echo "DEVICE is empty (xcrun devicectl list devices)"; exit 1; }

clean:
	rm -rf $(BUILD_DIR) $(GENERATED_DIR)
