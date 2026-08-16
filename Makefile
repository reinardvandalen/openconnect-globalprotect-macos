.PHONY: test icon build package install clean

test:
	swift test

icon:
	python3 ./Scripts/generate-icon.py

build:
	./Scripts/build-app.sh

package:
	./Scripts/package-app.sh

install: build
	@echo "OpenConnect VPN naar /Applications kopiëren..."
	@ditto "dist/OpenConnect VPN.app" "/Applications/OpenConnect VPN.app"
	@echo "Geïnstalleerd: /Applications/OpenConnect VPN.app"

clean:
	swift package clean
	rm -rf "dist/OpenConnect VPN.app" "dist/OpenConnectVPN-arm64.zip"
