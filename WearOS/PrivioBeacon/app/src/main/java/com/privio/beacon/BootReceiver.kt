package com.privio.beacon

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && BeaconIdentity.enabled(context)) {
            context.startForegroundService(Intent(context, BeaconService::class.java).setAction(BeaconService.ACTION_START))
        }
    }
}
