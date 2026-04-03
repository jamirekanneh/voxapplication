plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.voxapplication"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.voxapplication"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            storeFile = file('debug.keystore')
            storePassword = 'android'
            keyAlias = 'androiddebugkey'
            keyPassword = 'android'
        }

        create("release") {
            // Use environment variables for keystore credentials
            // Set these in your CI/CD or local environment
            storeFile = file(System.getenv('KEYSTORE_PATH') ?: 'upload-keystore.jks')
            storePassword = System.getenv('KEYSTORE_PASSWORD') ?: 'default_password'
            keyAlias = System.getenv('KEY_ALIAS') ?: 'upload'
            keyPassword = System.getenv('KEY_PASSWORD') ?: 'default_password'
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")

            // Use proper release signing configuration
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
