.PHONY: android ios build-all test-android

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Prefer JDK 21 for Gradle (Robolectric on compileSdk 36 requires it for unit tests).
export JAVA_HOME ?= $(shell /usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home 2>/dev/null)

android:
	cd $(ROOT) && ./gradlew :app:assembleDebug

test-android:
	cd $(ROOT) && ./gradlew :app:testDebugUnitTest

ios:
	cd $(ROOT)/ios && xcodegen generate && xcodebuild \
	  -project Meridian.xcodeproj \
	  -scheme Meridian \
	  -destination 'platform=iOS Simulator,name=iPhone 16' \
	  -quiet build

build-all: android test-android ios
	@echo "All builds succeeded."
