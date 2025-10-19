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
    
    // Fix namespace issue for flutter_vpn package
    if (project.name == "flutter_vpn") {
        afterEvaluate {
            if (project.hasProperty("android")) {
                val android = project.extensions.getByName("android")
                if (android is com.android.build.gradle.BaseExtension) {
                    android.namespace = "com.example.flutter_vpn"
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
