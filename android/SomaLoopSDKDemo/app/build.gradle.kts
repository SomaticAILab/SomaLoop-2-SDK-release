plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace="com.somaticai.somaloop.demo"
    compileSdk=36
    defaultConfig { applicationId="com.somaticai.somaloop.demo"; minSdk=26; targetSdk=36; versionCode=20; versionName="0.1.6-beta" }
    compileOptions { sourceCompatibility=JavaVersion.VERSION_17; targetCompatibility=JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget="17" }
}
dependencies { implementation("com.somaticai.somaloop:sdk:0.1.6-beta"); implementation("com.somaticai.somaloop:experimental:0.1.6-beta") }
