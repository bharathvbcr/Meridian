plugins {
  // AGP 9 provides built-in Kotlin compilation; no Compose here, so the Compose compiler
  // plugin is intentionally not applied.
  alias(libs.plugins.android.application)
}

android {
  namespace = "com.example.wear"
  compileSdk { version = release(36) { minorApiLevel = 1 } }

  defaultConfig {
    applicationId = "com.firebase.meridian.wear"
    minSdk = 30
    targetSdk = 34
    versionCode = 1
    versionName = "1.0"
  }

  buildTypes {
    release {
      isMinifyEnabled = false
    }
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
  }
}

dependencies {
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.wear.tiles)
  implementation(libs.androidx.wear.protolayout)
  implementation(libs.androidx.wear.protolayout.material)
  implementation(libs.play.services.wearable)
  implementation(libs.guava)
}
