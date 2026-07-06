buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        // Flutter Gradle plugin (flutter.groovy) imports groovy.xml.QName
        // which is not bundled with newer Gradle/Groovy distributions
        classpath("org.codehaus.groovy:groovy-xml:3.0.21")
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

// 仓库镜像（不拦截 Flutter 内置本地依赖，支持 CI 和国内开发）
allprojects {
    repositories {
        google()
        mavenCentral()
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/google")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
