plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.abyssrelay.p8v2n6"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "com.abyssrelay.p8v2n6"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += if (providers.gradleProperty("abyssX86").orNull == "true")
            listOf("arm64-v8a", "x86_64") else listOf("arm64-v8a") }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    androidResources {
        ignoreAssetsPattern = "!.svn:!.git:!.gitignore:!.ds_store:!*.scc:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~"
        noCompress += "pck"
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.godot.engine)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}

val exportGodotGame by tasks.registering(Exec::class) {
    val gameDirectory = rootProject.layout.projectDirectory.dir("game")
    val gamePack = layout.projectDirectory.file("src/main/assets/abyss.pck")
    inputs.files(fileTree(gameDirectory) { exclude(".godot/**") })
    outputs.file(gamePack)
    val bundledGodot = rootProject.file(".tools/Godot.app/Contents/MacOS/Godot")
    val linuxGodot = rootProject.file(".tools/godot")
    val executable = providers.environmentVariable("GODOT_BIN").orNull
        ?: if (bundledGodot.exists()) bundledGodot.absolutePath
        else if (linuxGodot.exists()) linuxGodot.absolutePath else "godot"
    commandLine(executable, "--headless", "--path", gameDirectory.asFile.absolutePath,
        "--export-pack", "Android", gamePack.asFile.absolutePath)
}

tasks.named("preBuild") { dependsOn(exportGodotGame) }
