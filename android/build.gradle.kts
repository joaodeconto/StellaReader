allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Keep every Android/Kotlin subproject on Java 17. This avoids generating
// Java 21 bytecode that cannot be consumed by the Java 17 toolchain used by CI.
// Applied after each subproject finishes its own evaluation, so it runs after
// plugin modules (e.g. pdfx) set their own, lower compileOptions default —
// otherwise theirs wins and Java/Kotlin compile tasks target different JVMs.
// :app is forced to evaluate eagerly above via evaluationDependsOn, so by the
// time we get here it may already be evaluated; afterEvaluate would throw on
// an already-evaluated project, so apply immediately in that case instead.
subprojects {
    val forceJvm17: () -> Unit = {
        tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }

        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }

    if (state.executed) {
        forceJvm17()
    } else {
        afterEvaluate { forceJvm17() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
