plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.test1"
    compileSdk = flutter.compileSdkVersion

    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true // ✅ Desugaring bật
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.test1"
        minSdk = 21 // ✅ Phải >= 21 để dùng multidex + desugaring
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true // ✅ Bắt buộc khi dùng desugar_jdk_libs
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Dùng phiên bản >= 2.1.4 để tránh lỗi
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ Thêm multidex để hỗ trợ desugaring
    implementation("androidx.multidex:multidex:2.0.1")
}
