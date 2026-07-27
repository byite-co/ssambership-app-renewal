import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리즈 서명(P0-5): android/key.properties 가 있으면 release(업로드) 키로 서명한다.
// key.properties 가 없을 때:
//   - 기본: release 산출물(bundle/assemble/packageRelease) 빌드가 즉시 실패한다.
//     → debug 서명 AAB 가 실수로 Play 에 첫 업로드돼 '잘못된 업로드 인증서'가
//       영구 등록되는 사고를 원천 차단(내부 테스트 첫 업로드 리스크 제거).
//   - 예외: -PallowInsecureSigning=true (또는 env ORG_GRADLE_PROJECT_allowInsecureSigning=true)
//     를 준 경우에만 debug 서명으로 폴백. CI 파이프라인 검증 전용이며 이 산출물은
//     스토어 제출 불가(자리표시 .env + debug 서명 = NOT-for-submission).
// key.properties 생성 절차·보관 수칙: docs/ANDROID_BUILD.md '릴리즈 서명'.
// ★ keystore·비밀번호는 절대 커밋 금지(android/.gitignore 가 차단).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
// keystore 부재 시 debug 서명 폴백을 '명시적으로' 허용할 때만 true(CI 파이프라인 검증용).
val allowInsecureSigning =
    (project.findProperty("allowInsecureSigning")?.toString()?.toBoolean()) ?: false

android {
    namespace = "com.ssambership.edu"
    // 명시 고정(P0-6): Google Play 신규 앱 요건 = 2026-08-31부터 targetSdk 36
    // (Android 16) 이상. Flutter 3.44.4 기본값과 동일 값을 위임 대신 고정해
    // SDK 업그레이드가 조용히 타깃을 바꾸지 못하게 한다.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ssambership.edu"
        // 명시 고정(P0-6). minSdk 24 = Flutter 3.44 기본(Android 7.0).
        minSdk = 24
        targetSdk = 36
        // versionCode/Name 은 pubspec.yaml 의 version(x.y.z+N)에서 온다 —
        // 스토어 업로드마다 +N 을 반드시 증가(규약: HANDOFF §3-1-B).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties 존재 시 release(업로드) 키로 서명. 부재 시 debug 서명이
            // 배선되지만, release 산출물 빌드는 아래 taskGraph 가드가(opt-in 없을 때)
            // 실패시키므로 debug 서명 AAB 가 실제로 만들어지지 않는다.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// release keystore 부재 시 '실제 release 산출물'을 만들 때만 빌드를 실패시킨다.
// task 그래프 확정 후 판정하므로 debug/profile 빌드·flutter run·analyze·test 는 영향 없음.
if (!hasReleaseKeystore && !allowInsecureSigning) {
    gradle.taskGraph.whenReady {
        val buildingRelease = allTasks.any { task ->
            val n = task.name
            (n.startsWith("bundle") || n.startsWith("assemble") || n.startsWith("package")) &&
                n.endsWith("Release")
        }
        if (buildingRelease) {
            throw GradleException(
                "release 빌드에 android/key.properties(업로드 keystore)가 없습니다. " +
                    "스토어 제출용 AAB 는 반드시 release(업로드) 키로 서명해야 합니다. " +
                    "키 생성·설정 절차: docs/ANDROID_BUILD.md '릴리즈 서명'. " +
                    "CI 파이프라인 검증처럼 debug 서명 폴백이 의도된 경우에만 " +
                    "-PallowInsecureSigning=true (env ORG_GRADLE_PROJECT_allowInsecureSigning=true) 로 빌드하세요.",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
