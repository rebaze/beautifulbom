# Beautiful Bill of Materials — build entry points. Run from apps/beautiful-bom/.
SHELL := /bin/bash
PKG := Packages/BOMCore
GEN := Fixtures/generated
BENCH = $(PKG)/.build/release/bbom-bench
SIZES := 1 10 50

APP := build/Build/Products/Debug/BeautifulBOM.app
.PHONY: test bench-build fixtures bench project app snapshot clean

test:
	cd $(PKG) && swift test

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

project:
	xcodegen generate --quiet

app: project
	set -o pipefail; xcodebuild -project BeautifulBOM.xcodeproj -scheme BeautifulBOM -configuration Debug -derivedDataPath build build | xcbeautify --quiet

# make snapshot FILE=<json> OUT=<png> [SELECT=<json-pointer>]
snapshot:
	timeout 30 $(APP)/Contents/MacOS/BeautifulBOM -ApplePersistenceIgnoreState YES \
	  --open "$(abspath $(FILE))" --snapshot "$(abspath $(OUT))" $(if $(SELECT),--select '$(SELECT)')

clean:
	rm -rf build Packages/BOMCore/.build
