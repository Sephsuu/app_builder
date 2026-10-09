allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// The plugin sets cppFlags but omits cFlags. Its ggml quantization and CPU
// kernels are C sources, so debug APKs otherwise compile them without -O.
// Keep this override in the app rather than editing the global pub cache.
subprojects {
    if (name == "whisper_cpp_flutter_plus") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                defaultConfig {
                    externalNativeBuild {
                        cmake {
                            cFlags.add("-O3")
                        }
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
