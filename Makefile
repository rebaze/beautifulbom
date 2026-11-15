# Beautiful Bill of Materials — build entry points. Run from apps/beautiful-bom/.
PKG := Packages/BOMCore

.PHONY: test clean

test:
	cd $(PKG) && swift test

clean:
	rm -rf build $(PKG)/.build
