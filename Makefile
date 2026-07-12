.PHONY: android ios build-all test-android \
	gen-icon gen-feature-graphic gen-earth build-cities semantic-bench assets

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

# --- Python tooling (store assets, map texture, city DB, semantic bench) ---

gen-icon:
	cd $(ROOT) && python store_assets/gen_icon.py

gen-feature-graphic:
	cd $(ROOT) && python store_assets/gen_feature_graphic.py

gen-earth:
	cd $(ROOT) && python tools/gen_earth_texture.py

build-cities:
	cd $(ROOT) && python tools/citygen/build_cities_db.py

semantic-bench:
	cd $(ROOT)/tools/semantic_layer && python -m semantic_layer.benchmark --queries 200

assets: gen-icon gen-feature-graphic
	@echo "Store assets regenerated."
