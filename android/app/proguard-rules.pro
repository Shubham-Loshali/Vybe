# Keep Flutter internal utility classes accessed via JNI by path_provider_android
-keep class io.flutter.util.** { *; }

# just_audio & ExoPlayer ProGuard Rules
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.ryanheise.just_audio.**

# Media3 / ExoPlayer rules (just_audio uses Media3/ExoPlayer natively)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**

# AudioService & AudioSession
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**
-keep class com.ryanheise.audio_session.** { *; }
-dontwarn com.ryanheise.audio_session.**

# ExoPlayer legacy
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Keep generic annotations and reflection classes used by audio plugins
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
