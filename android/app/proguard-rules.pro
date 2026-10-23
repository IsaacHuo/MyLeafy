# MyLeafy Android release rules.

# kotlinx.serialization generates serializers by name; keep the generated members.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer {
    *** descriptor;
}
-keepclasseswithmembers class com.myleafy.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep class com.myleafy.android.**$$serializer { *; }

# Room instantiates generated database/DAO implementations reflectively.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
-keep class com.myleafy.android.core.data.local.**_Impl { *; }

# WorkManager instantiates Worker subclasses from their class names.
-keep class * extends androidx.work.ListenableWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}

# OkHttp 4 optional TLS providers are not bundled with the app.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn kotlinx.coroutines.debug.**
