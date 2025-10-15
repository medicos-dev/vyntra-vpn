# Keep Flutter and OpenVPN plugin classes
-keep class io.flutter.** { *; }
-keep class dev.flutter.** { *; }
-keep class com.paascloud.** { *; }
-keep class net.openvpn.** { *; }
-keep class de.blinkt.openvpn.** { *; }

# Keep Google Play Core classes (required by Flutter)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep classes with JNI/onCreate used by plugins
-keepclassmembers class * {
    native <methods>;
}

# Keep enum names & values used via reflection
-keepclassmembers enum * { *; }

# Keep required annotations
-keepattributes *Annotation*

# Do not warn on openvpn/ics libs
-dontwarn net.openvpn.**
-dontwarn de.blinkt.openvpn.**

