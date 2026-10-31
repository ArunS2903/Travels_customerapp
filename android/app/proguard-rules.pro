# R8 rules for the release build.
#
# Flutter's own plugin ships the Flutter engine rules, so what is left is the
# handful of libraries that rely on reflection and would otherwise be stripped.

# --- Google Play Services / Maps -------------------------------------------
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.**

# --- Firebase Cloud Messaging ----------------------------------------------
# FCM instantiates these by name from the manifest.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.datatransport.** { *; }
-dontwarn com.google.firebase.**

# --- flutter_local_notifications -------------------------------------------
# Scheduled-notification payloads are deserialised with Gson, which needs the
# generic signatures and the model classes intact.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.dexterous.**

# --- Kotlin coroutines ------------------------------------------------------
-dontwarn kotlinx.coroutines.**

# --- Keep source line numbers in crash reports -----------------------------
# Without this a stack trace from the field is unreadable. The original file
# name is still hidden.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
