# SkyNest Android release keep rules.
# R8 shrinking/minification is disabled in this release while startup is diagnosed.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
