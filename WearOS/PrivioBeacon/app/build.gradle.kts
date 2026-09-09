plugins {
    id("com.android.application")
}

android {
    namespace = "com.privio.beacon"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.privio.beacon"
        minSdk = 30
        targetSdk = 36
        versionCode = 3
        versionName = "0.2.1"
    }
}

dependencies {
    implementation("com.google.zxing:core:3.5.4")
}
