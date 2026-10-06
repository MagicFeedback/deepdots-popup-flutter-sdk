group = "com.deepdots.deepdots_popups"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

// SDK nativo de Deepdots (KMP) vendorizado como repo Maven local, para la prueba de concepto.
// En producción vendría de Maven Central (com.deepdots.sdk:shared-android).
// Se registra en el proyecto raíz (no en `allprojects` de este script, que solo alcanza al
// plugin): la dependencia transitiva la resuelve también el módulo `:app` del host.
val deepdotsLocalRepo = file("maven")

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri(deepdotsLocalRepo) }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.deepdots.deepdots_popups"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.deepdots.sdk:shared-android:0.6.0")
    // Scope propio del plugin para las llamadas `suspend` del SDK (setContactAttributes).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
