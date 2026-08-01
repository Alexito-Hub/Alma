package pro.alma.piwkenyeyu

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing whether the Alma server is answering.
 *
 * Values come from the Flutter side, which polls `GET /health` when the app
 * opens and on every background sync tick. The header block takes the neo
 * palette colour matching the verdict.
 */
class ServerWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val status = widgetData.getString("server_status", null).orEmpty()
        val detail = widgetData.getString("server_detail", null).orEmpty()
        val at = widgetData.getString("server_at", null).orEmpty()

        val label = when (status) {
            "ok" -> "Todo bien"
            "degraded" -> "Con avisos"
            "error" -> "Con fallos"
            "offline" -> "Sin conexión"
            else -> "Sin datos"
        }
        val accent = when (status) {
            "ok" -> Color.parseColor("#86E0AF")
            "degraded" -> Color.parseColor("#FFD645")
            "error", "offline" -> Color.parseColor("#FF8A66")
            else -> Color.parseColor("#FFFFFF")
        }

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_server).apply {
                setInt(R.id.server_label, "setBackgroundColor", accent)
                setTextViewText(R.id.server_status, label)
                setTextViewText(R.id.server_detail, detail)
                setTextViewText(R.id.server_at, if (at.isBlank()) "" else "revisado $at")
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
