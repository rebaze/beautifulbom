# Beautiful Bill of Materials — build entry points. Run from apps/beautiful-bom/.
PKG := Packages/BOMCore
GEN := Fixtures/generated
BENCH = $(PKG)/.build/release/bbom-bench
SIZES := 1 10 50

.PHONY: test bench-build fixtures bench clean

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

clean:
	rm -rf build Packages/BOMCore/.build
