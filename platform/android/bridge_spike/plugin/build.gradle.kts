import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.nocapsfun.bridge"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

dependencies {
    compileOnly("org.godotengine:godot:4.7.2.stable")
    // Solana Mobile Wallet Adapter client. The same coordinate must also be
    // declared to the Godot export (addons/nocaps_bridge/export_plugin.gd) so it
    // reaches the APK: a raw .aar dependency carries no transitive metadata.
    implementation("com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.0.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // MWA's ActivityResultSender is bound to a ComponentActivity; Godot's
    // GodotActivity is a FragmentActivity, so the type must be on the classpath.
    implementation("androidx.activity:activity-ktx:1.10.1")
}

tasks.register<Copy>("installPluginArtifacts") {
    dependsOn("assembleDebug", "assembleRelease")
    from(layout.buildDirectory.file("outputs/aar/plugin-debug.aar")) {
        into("debug")
    }
    from(layout.buildDirectory.file("outputs/aar/plugin-release.aar")) {
        into("release")
    }
    into(rootProject.file("../../../addons/nocaps_bridge/bin"))
}
