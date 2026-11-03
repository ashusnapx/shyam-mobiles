# Razorpay (https://razorpay.com/docs/payments/payment-gateway/android-integration/standard/)
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

# PhonePe (phonepe_payment_sdk ships this rule for its own build only, not as a consumer rule)
-keep class com.phonepe.** { *; }
-dontwarn com.phonepe.**
