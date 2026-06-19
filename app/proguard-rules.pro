# Keep line numbers in stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep Kotlin metadata so reflection-based libs (Room, serialization) work
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** { volatile <fields>; }

# Kotlinx serialization
-keepattributes *Annotation*
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    *** Companion;
    *** INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1>$$serializer { *; }

# Room — keep all entity and DAO classes
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keep @androidx.room.Dao class *
-keepclassmembers @androidx.room.Entity class * { *; }
-keepclassmembers @androidx.room.Dao class * { *; }

# DataStore
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { <fields>; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ML Kit GenAI
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Jetpack Compose — keep lambda names for better crash traces
-keepclassmembers class androidx.compose.** { *; }
-dontwarn androidx.compose.**

# Glance (Widgets)
-keep class androidx.glance.** { *; }
-dontwarn androidx.glance.**

# WorkManager
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Haze (glass blur library)
-dontwarn dev.chrisbanes.haze.**

# Keep app's interop contract (read via reflection by ContentProvider)
-keep class com.example.core.interop.** { *; }

# Keep data classes used in DB / serialization
-keep class com.example.core.data.** { *; }

# Keep AI result types
-keep class com.example.core.ai.AiResult { *; }
-keep class com.example.core.ai.AiResult$* { *; }
