# SPDX-License-Identifier: GPL-3.0-or-later

BUILD_DIR ?= build
QML_FILES := $(shell find src/qml -type f -name '*.qml' -print)
SHELL_FILES := $(shell find scripts tests -type f -name '*.sh' -print)

.PHONY: all configure check check-build check-common check-portable format install package package-deb package-rpm release sign-release

all: configure
	cmake --build $(BUILD_DIR)

configure:
	cmake -S . -B $(BUILD_DIR) -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr

check-common:
	./tests/check-source.sh
	./tests/check-release.sh
	shellcheck $(SHELL_FILES)
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v tests/test_snapshot.py tests/test_icon_geometry.py

check-portable: check-common
	./tests/check-snapshot.sh

check-build: check-common all
	./scripts/run-qml-tool.sh qmllint --unqualified disable --max-warnings 0 $(QML_FILES)
	ctest --test-dir $(BUILD_DIR) --output-on-failure
	./tests/check-package.sh $(BUILD_DIR)

check: check-portable check-build

format:
	./scripts/run-qml-tool.sh qmlformat -i $(QML_FILES)

package: check
	./scripts/build-release.sh tgz

package-deb: check
	./scripts/build-release.sh deb

package-rpm: check
	./scripts/build-release.sh rpm

release: check
	./scripts/build-release.sh all

sign-release:
	./scripts/sign-release.sh

install: all
	cmake --install $(BUILD_DIR)
