# flutter_gemma / MediaPipe — proto classes missing from the compile classpath
# (referenced only from unused profiler/template APIs).
-dontwarn com.google.mediapipe.**

# Keep everything the native engine reaches via JNI/reflection — R8 renaming
# these would compile fine but crash at runtime on model init.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.ai.edge.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class com.google.flatbuffers.** { *; }
