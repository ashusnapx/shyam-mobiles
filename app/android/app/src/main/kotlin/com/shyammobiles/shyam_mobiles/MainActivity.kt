package com.shyammobiles.shyam_mobiles

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// A FragmentActivity: phonepe_payment_sdk registers its result launcher on one and crashes on a plain FlutterActivity.
class MainActivity : FlutterFragmentActivity() {
    // Instagram / Facebook Stories (lib/core/stories.dart): Meta's "add to story" intents, by app name
    private val stories = mapOf(
        "instagram" to "com.instagram.share.ADD_TO_STORY",
        "facebook" to "com.facebook.stories.ADD_TO_STORY",
    )

    private fun storyIntent(app: String) = Intent(stories.getValue(app)).setType("image/png")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shyam_mobiles/stories").setMethodCallHandler { call, result ->
            when (call.method) {
                "installed" -> result.success(stories.keys.filter { packageManager.resolveActivity(storyIntent(it), 0) != null })
                "share" -> {
                    val app = call.argument<String>("app")
                    val png = call.argument<ByteArray>("png")
                    if (app !in stories || png == null) return@setMethodCallHandler result.error("bad_args", null, null)
                    // always the same file in our own cache: Dart never names a path
                    val file = File(File(cacheDir, "stories").apply { mkdirs() }, "story.png").apply { writeBytes(png) }
                    val uri = FileProvider.getUriForFile(this, "$packageName.stories", file)
                    val appId = call.argument<String>("appId")
                    val intent = storyIntent(app!!).setDataAndType(uri, "image/png")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        .putExtra("source_application", appId) // Instagram
                        .putExtra("com.facebook.platform.extra.APPLICATION_ID", appId) // Facebook
                    val target = packageManager.resolveActivity(intent, 0)
                    if (target == null) {
                        result.success(false)
                    } else {
                        grantUriPermission(target.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        startActivity(intent)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

// Its own class so its manifest entry never clashes with a plugin's androidx FileProvider.
class StoryFileProvider : FileProvider()
