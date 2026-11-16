# Beautiful Bill of Materials — build entry points. Run from the repository root.
SHELL := /bin/bash
PKG := Packages/BOMCore
GEN := Fixtures/generated
BENCH = $(PKG)/.build/release/bbom-bench
SIZES := 1 10 50

CONFIG ?= Debug
APP = build/Build/Products/$(CONFIG)/BeautifulBOM.app
.PHONY: screenshots test strings-check bench-build fixtures bench project app install dmg snapshot clean parity-refresh

test: strings-check
	cd $(PKG) && swift test

# Every workshop string has English and German, and none claims conformity.
strings-check:
	python3 -I scripts/check-strings.py

# Regenerate rio's results for the parity tests (needs rio on PATH).
parity-refresh:
	python3 -I scripts/rio-parity.py

bench-build:
	cd $(PKG) && swift build -c release --product bbom-bench

fixtures: bench-build
	mkdir -p $(GEN)
	for s in $(SIZES); do \
	  $(BENCH) generate --size $$s --out $(GEN)/$${s}mb.json; \
	  $(BENCH) generate --size $$s --minified --out $(GEN)/$${s}mb-min.json; \
	done

bench: bench-build
	for f in Fixtures/public/*.json $(foreach s,$(SIZES),$(GEN)/$(s)mb.json $(GEN)/$(s)mb-min.json); do $(BENCH) parse $$f; done
	for f in Fixtures/public/*.json $(foreach s,$(SIZES),$(GEN)/$(s)mb.json $(GEN)/$(s)mb-min.json); do $(BENCH) analyse $$f; done

project:
	xcodegen generate --quiet

app: project
	set -o pipefail; xcodebuild -project BeautifulBOM.xcodeproj -scheme BeautifulBOM -configuration $(CONFIG) -derivedDataPath build build | xcbeautify --quiet

# The Release app in ~/Applications, so Spotlight, Launchpad and the Dock find it.
install:
	$(MAKE) app CONFIG=Release
	rm -rf "$(HOME)/Applications/BeautifulBOM.app"
	ditto build/Build/Products/Release/BeautifulBOM.app "$(HOME)/Applications/BeautifulBOM.app"
	@echo "Installed: $(HOME)/Applications/BeautifulBOM.app"

# A disk image to hand out: the Release app and a link to Applications, to drag across.
# Signed ad hoc only: on another Mac, Gatekeeper asks once (System Settings › Privacy & Security
# › Open Anyway). A Developer ID signature and notarization need rebaze's credentials.
VERSION := $(shell sed -n 's/.*CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml)
DMG := build/BeautifulBOM-$(VERSION).dmg
dmg:
	$(MAKE) app CONFIG=Release
	rm -rf build/dmg "$(DMG)" && mkdir -p build/dmg
	ditto build/Build/Products/Release/BeautifulBOM.app "build/dmg/Beautiful BOM.app"
	ln -s /Applications build/dmg/Applications
	hdiutil create -quiet -volname "Beautiful BOM $(VERSION)" -srcfolder build/dmg -fs HFS+ -format UDZO "$(DMG)"
	hdiutil verify -quiet "$(DMG)"
	@echo "Disk image: $(DMG)"

# make snapshot FILE=<json> OUT=<png> [SELECT=<pointer>] [VIEW=<tab>] [COMPONENT=<bom-ref>]
#   [EVIDENCE=<rule id>] [FIND=<text>] [POINT=<bom-ref>] [SIZE=1440x900] [TEXT=24] [APPEARANCE=dark|light] [UILANG=de|en]
snapshot:
	timeout 30 $(APP)/Contents/MacOS/BeautifulBOM -ApplePersistenceIgnoreState YES \
	  --open "$(abspath $(FILE))" --snapshot "$(abspath $(OUT))" $(if $(SELECT),--select '$(SELECT)') \
	  $(if $(VIEW),--view $(VIEW)) $(if $(COMPONENT),--component '$(COMPONENT)') $(if $(EVIDENCE),--evidence $(EVIDENCE)) \
	  --window-size $(or $(SIZE),1440x900) $(if $(TEXT),--text-size $(TEXT)) $(if $(APPEARANCE),--appearance $(APPEARANCE)) \
	  $(if $(UILANG),--language $(UILANG)) $(if $(FIND),--find '$(FIND)') $(if $(POINT),--point '$(POINT)')

clean:
	rm -rf build Packages/BOMCore/.build

# Every workshop view as PNG in build/screenshots (the LAN gallery serves that folder).
LARAVEL := Fixtures/public/laravel-7.12.0.cdx-1.4.json
CERN := Fixtures/public/cern-lhc-vdm-editor.cdx.json
screenshots: app
	mkdir -p build/screenshots
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-overview-laravel.png VIEW=overview UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-overview-laravel-24.png VIEW=overview TEXT=24 UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-overview-laravel-de.png VIEW=overview UILANG=de
	$(MAKE) -s snapshot FILE=$(CERN) OUT=build/screenshots/w-overview-cern-dark.png VIEW=overview APPEARANCE=dark UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-drawer-timestamp.png VIEW=overview EVIDENCE=sbom.timestamp UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-composition-laravel.png VIEW=composition UILANG=en
	$(MAKE) -s snapshot FILE=$(CERN) OUT=build/screenshots/w-composition-cern.png VIEW=composition UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-completeness-laravel.png VIEW=completeness UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-completeness-laravel-de.png VIEW=completeness EVIDENCE=components.deployableHash UILANG=de
	$(MAKE) -s snapshot FILE=Fixtures/rio/bsi-pass.cdx.json OUT=build/screenshots/w-completeness-bsi-pass.png VIEW=completeness UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-components-laravel.png VIEW=components UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-component-lexer.png COMPONENT=doctrine/lexer-1.2.3.0 UILANG=en
	$(MAKE) -s snapshot FILE=$(LARAVEL) OUT=build/screenshots/w-component-lexer-24.png COMPONENT=doctrine/lexer-1.2.3.0 TEXT=24 UILANG=en
	$(MAKE) -s snapshot FILE=Fixtures/edge/duplicates.json OUT=build/screenshots/w-source-only.png
