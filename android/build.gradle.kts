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
// Applied in afterEvaluate so it runs after plugin modules (e.g. pdfx) set
// their own, lower compileOptions default — otherwise theirs wins and Java
// and Kotlin compile tasks end up targeting different JVM versions.
subprojects {
    afterEvaluate {
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
