package pro.alma.piwkenyeyu

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing the partner's current "siente".
 *
 * Read-only: the Flutter side writes the values (couple channel while the app
 * is open, background sync tick otherwise) and asks for a redraw. Tapping it
 * opens Alma.
 */
class StatusWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val author = widgetData.getString("status_author", null) ?: "Tu pareja"
        val text = widgetData.getString("status_text", null).orEmpty()
        val at = widgetData.getString("status_at", null).orEmpty()

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_status).apply {
                setTextViewText(R.id.status_author, "${author.uppercase()} SIENTE")
                setTextViewText(
                    R.id.status_text,
                    if (text.isBlank()) "…esperando un pensamiento" else text
                )
                setTextViewText(R.id.status_at, if (at.isBlank()) "" else "actualizado $at")
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
