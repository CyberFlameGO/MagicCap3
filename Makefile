UNAME_S := $(shell uname -s)
NODE_ARCH := $(shell node -e 'console.log(process.arch)' | tr -d '\n')
GO_ARCH := $(shell dpkg --print-architecture | tr -d '\n')

ELECTRON_PACKAGER_DARWIN_ARGS := --icon assets/icon.icns --ignore "Makefile|build_tmp" --app-category-type "public.app-category.productivity" --app-bundle-id "org.magiccap.magiccap"
ELECTRON_PACKAGER_LINUX_ARGS := --icon assets/icon.icns

YARN := npm_config_yes=true npx yarn

.PHONY: build package darwin-app-sign darwin-ci linux-ci dev

build:
	# Build all of the assets and JavaScript.
ifeq ($(UNAME_S),Darwin)
	rm -rf node_modules && PRODUCTION_BUILD=1 $(YARN) --ignore-scripts --frozen-lockfile
else
	rm -rf node_modules && PRODUCTION_BUILD=1 $(YARN) --frozen-lockfile
endif
	mkdir -p dist
	rm -rf dist
	WEBPACK_ENV=production node webpacker.js
	$(YARN) run build:copy
	$(YARN) run build:hash

	# Clean the bundles folder.
	mkdir -p bundles
	rm -rf bundles

ifeq ($(UNAME_S),Darwin)
	# Clone my fork of @electron/universal and build the patched version.
	mkdir -p build_tmp
	rm -rf build_tmp
	mkdir build_tmp
	cd build_tmp && git clone https://github.com/JakeMakesStuff/universal
	cd build_tmp/universal && $(YARN) && $(YARN) build
	mv build_tmp/universal/dist build_tmp
	rm -rf build_tmp/universal

	# Make sure the applications libraries are compiled for amd64.
	rm -rf node_modules && PRODUCTION_BUILD=1 npm_config_arch=x64 npm_config_platform=darwin $(YARN) --frozen-lockfile
	node_modules/.bin/electron-rebuild -a x64

	# Compile our Go binaries for amd64.
	cd gif && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -o ../dist/gif
	cd inplace_upgrade && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -o ../dist/inplace_upgrade
	cd sftp && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -o ../dist/sftp

	# Build libscreenshot for amd64.
	cd libscreenshot && HOME=~/.electron-gyp npm_config_yes=true npx node-gyp rebuild --runtime=electron --target=17.1.0 --dist-url=https://electronjs.org/headers --arch=x64
	mkdir -p dist/libscreenshot/Release
	mv libscreenshot/build/Release/screenshot.node dist/libscreenshot/Release
	rm -rf libscreenshot/build

	# Build libnotch for amd64.
	cd libnotch && HOME=~/.electron-gyp npm_config_yes=true npx node-gyp rebuild --runtime=electron --target=17.1.0 --dist-url=https://electronjs.org/headers --arch=x64
	mkdir -p dist/libnotch/Release
	mv libnotch/build/Release/notch.node dist/libnotch/Release
	rm -rf libnotch/build

	# Make the amd64 bundle.
	mv node_modules/better-sqlite3/build/Release/better_sqlite3.node build_tmp
	rm -rf node_modules/better-sqlite3/build
	mkdir -p node_modules/better-sqlite3/build/Release
	mv build_tmp/better_sqlite3.node node_modules/better-sqlite3/build/Release
	mv node_modules/sharp/build/Release/sharp-*.node build_tmp
	rm -rf node_modules/sharp/build
	mkdir -p node_modules/sharp/build/Release
	mv build_tmp/sharp-*.node node_modules/sharp/build/Release
	rm node_modules/.yarn-integrity
	node_modules/.bin/electron-packager . MagicCap --out bundles --arch x64 $(ELECTRON_PACKAGER_DARWIN_ARGS)

	# Make sure the applications libraries are compiled for arm64.
	rm -rf node_modules && PRODUCTION_BUILD=1 npm_config_arch=arm64 npm_config_platform=darwin $(YARN) --frozen-lockfile
	node_modules/.bin/electron-rebuild -a arm64

	# Compile our Go binaries for arm64.
	cd gif && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -o ../dist/gif
	cd inplace_upgrade && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -o ../dist/inplace_upgrade
	cd sftp && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -o ../dist/sftp

	# Build libscreenshot for arm64.
	rm -rf dist/libscreenshot
	cd libscreenshot && HOME=~/.electron-gyp npm_config_yes=true npx node-gyp rebuild --runtime=electron --target=17.1.0 --dist-url=https://electronjs.org/headers --arch=arm64
	mkdir -p dist/libscreenshot/Release
	mv libscreenshot/build/Release/screenshot.node dist/libscreenshot/Release
	rm -rf libscreenshot/build

	# Build libnotch for arm64.
	rm -rf dist/libnotch
	cd libnotch && HOME=~/.electron-gyp npm_config_yes=true npx node-gyp rebuild --runtime=electron --target=17.1.0 --dist-url=https://electronjs.org/headers --arch=arm64
	mkdir -p dist/libnotch/Release
	mv libnotch/build/Release/notch.node dist/libnotch/Release
	rm -rf libnotch/build

	# Make the arm64 bundle.
	mv node_modules/better-sqlite3/build/Release/better_sqlite3.node build_tmp
	rm -rf node_modules/better-sqlite3/build
	mkdir -p node_modules/better-sqlite3/build/Release
	mv build_tmp/better_sqlite3.node node_modules/better-sqlite3/build/Release
	mv node_modules/sharp/build/Release/sharp-*.node build_tmp
	rm -rf node_modules/sharp/build
	mkdir -p node_modules/sharp/build/Release
	mv build_tmp/sharp-*.node node_modules/sharp/build/Release
	rm node_modules/.yarn-integrity
	node_modules/.bin/electron-packager . MagicCap --out bundles --arch arm64 $(ELECTRON_PACKAGER_DARWIN_ARGS)

	# Fuse the app bundles.
	rm -rf node_modules/@electron/universal/dist
	cp -r build_tmp/dist node_modules/@electron/universal
	DEBUG=* node build/scripts/fuse_bundles.js
else
	# Build the native binaries for our architecture.
	node_modules/.bin/electron-rebuild

	# Build libscreenshot.
	$(YARN) run build:native

	# Build the Go binaries.
	cd gif && go build -o ../dist/gif
	cd sftp && go build -o ../dist/sftp

	# Package the application.
	node_modules/.bin/electron-packager . MagicCap --out bundles $(ELECTRON_PACKAGER_LINUX_ARGS)
endif

	# Clean the temp build folder.
	rm -rf build_tmp

	# Finalize and then send the success message.
ifeq ($(UNAME_S),Darwin)
	rm -rf node_modules
	@echo "You have successfully compiled MagicCap! Note that due to how macOS's release is built, your node_modules was mutated and has therefore been removed. If you want to develop MagicCap, please run yarn before using any scripts."
else
	@echo "You have successfully compiled MagicCap!"
endif

package:
ifeq ($(UNAME_S),Darwin)
	# Package as a .dmg.
	node_modules/.bin/electron-installer-dmg bundles/MagicCap.app --out bundles --title MagicCap
else
	# Package as a .deb.
	mv bundles/MagicCap-linux-$(NODE_ARCH)/MagicCap bundles/MagicCap-linux-$(NODE_ARCH)/magiccap
	node_modules/.bin/electron-installer-debian --src bundles/MagicCap-linux-$(NODE_ARCH)/ --dest bundles/ --productName MagicCap --name MagicCap --arch $(GO_ARCH) --icon assets/icon.png
	mv bundles/MagicCap-linux-$(NODE_ARCH)/magiccap bundles/MagicCap-linux-$(NODE_ARCH)/MagicCap

	# Package as a .rpm.
	mv bundles/MagicCap-linux-$(NODE_ARCH)/MagicCap bundles/MagicCap-linux-$(NODE_ARCH)/magiccap
	node_modules/.bin/electron-installer-redhat --src bundles/MagicCap-linux-$(NODE_ARCH)/ --dest bundles/ --productName MagicCap --name MagicCap --arch $(GO_ARCH) --icon assets/icon.png
	mv bundles/MagicCap-linux-$(NODE_ARCH)/magiccap bundles/MagicCap-linux-$(NODE_ARCH)/MagicCap
endif

darwin-app-sign:
	node_modules/.bin/electron-osx-sign bundles/MagicCap.app \
		--entitlements build/entitlements.mac.plist \
		--platform darwin \
		--no-gatekeeper-assess \
		--binaries bundles/MagicCap.app/Contents/Resources/app-arm64/dist/gif \
		--binaries bundles/MagicCap.app/Contents/Resources/app-x64/dist/gif \
		--binaries bundles/MagicCap.app/Contents/Resources/app-arm64/dist/inplace_upgrade \
		--binaries bundles/MagicCap.app/Contents/Resources/app-x64/dist/inplace_upgrade \
		--binaries bundles/MagicCap.app/Contents/Resources/app-arm64/dist/sftp \
		--binaries bundles/MagicCap.app/Contents/Resources/app-x64/dist/sftp

darwin-ci:
	# Build everything ready to be pushed.
	make
	$(YARN)
	make darwin-app-sign
	make package

	# zip the inner of the app.
	cd bundles/MagicCap.app && zip -r ../../dist/app_inners.zip .

	# Push the commit to S3.
	aws s3 sync app_inners.zip s3://$(S3_BUCKET)/darwin/$(shell cat dist/commit_hash).zip --endpoint=$(S3_ENDPOINT) --acl public-read

	# Insert to the commit table.
	COMMIT_HASH=$(shell cat dist/commit_hash) DARWIN_CDN_URL=https://cdn.magiccap.org/darwin/$(shell cat dist/commit_hash).zip API_KEY=$(API_KEY) node ./build/scripts/push_to_updater.js

linux-ci:
	make
	make package

dev:
	$(YARN)
	$(YARN) run dev-run
