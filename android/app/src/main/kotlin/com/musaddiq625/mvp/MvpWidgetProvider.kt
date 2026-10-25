package com.musaddiq625.mvp

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class MvpWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.mvp_widget).apply {
            setTextViewText(
                R.id.headline,
                widgetData.getString("headline", "—") ?: "—",
            )
            setTextViewText(
                R.id.line,
                widgetData.getString("line", "alive-ish.") ?: "alive-ish.",
            )
            setProgressBar(
                R.id.bar,
                100,
                widgetData.getInt("fractionPct", 100),
                false,
            )

            // Taps hit Dart in the background — the app never opens.
            setOnClickPendingIntent(
                R.id.btn_ate,
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("mvp://ate")))
            setOnClickPendingIntent(
                R.id.btn_drank,
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("mvp://drank")))

            // Tap the number → open the app.
            setOnClickPendingIntent(
                R.id.headline,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java))
          }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
