package pro.alma.piwkenyeyu

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen widget showing the partner's current "siente": their line of
 * text and, when they attached one, the snapshot that came with it.
 *
 * Read-only: the Flutter side writes the values (couple channel while the app
 * is open, background sync tick otherwise) and asks for a redraw. Tapping it
 * opens Alma.
 */
class StatusWidgetProvider : HomeWidgetProvider() {

    /** Keeps the bitmap well under the ~1MB RemoteViews binder budget. */
    private val maxPhotoWidth = 480

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val author = widgetData.getString("status_author", null) ?: "Tu pareja"
        val text = widgetData.getString("status_text", null).orEmpty()
        val at = widgetData.getString("status_at", null).orEmpty()
        val photo = decodePhoto(widgetData.getString("status_photo", null))

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_status).apply {
                setTextViewText(R.id.status_author, "${author.uppercase()} SIENTE")
                setTextViewText(
                    R.id.status_text,
                    when {
                        text.isNotBlank() -> text
                        photo != null -> "Te compartió una instantánea"
                        else -> "…esperando un pensamiento"
                    }
                )
                setTextViewText(R.id.status_at, if (at.isBlank()) "" else "actualizado $at")

                if (photo != null) {
                    setImageViewBitmap(R.id.status_photo, photo)
                    setViewVisibility(R.id.status_photo, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.status_photo, View.GONE)
                }

                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Load the snapshot downscaled, or null when there isn't one. */
    private fun decodePhoto(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        val file = File(path)
        if (!file.exists()) return null

        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0) return null

            var sample = 1
            while (bounds.outWidth / sample > maxPhotoWidth) sample *= 2

            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply { inSampleSize = sample }
            )
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }
}
