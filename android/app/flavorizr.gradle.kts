import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.taproot.app.dev"
            resValue(type = "string", name = "app_name", value = "Taproot Dev")
        }
        create("stg") {
            dimension = "flavor-type"
            applicationId = "com.taproot.app.stg"
            resValue(type = "string", name = "app_name", value = "Taproot Stg")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.taproot.app"
            resValue(type = "string", name = "app_name", value = "Taproot")
        }
    }

    buildFeatures.resValues = true
}