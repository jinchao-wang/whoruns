package com.wjc.whoruns

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * 取别的 App 的图标。
 *
 * 系统没有公开的「读图标」接口，只能自己按包名去 PackageManager 要，
 * 再把 Drawable 画成位图编成 PNG 传给 Flutter。
 */
object AppIcons {

    /** 一次最多取多少个，避免把内存吃满。 */
    private const val MAX_ICONS = 80

    private const val SIZE = 96

    fun load(context: Context, packages: List<String>): Map<String, String> {
        val pm = context.packageManager
        val out = HashMap<String, String>()
        for (pkg in packages.take(MAX_ICONS)) {
            try {
                val info = pm.getApplicationInfo(pkg, 0)
                val drawable = pm.getApplicationIcon(info)
                val bitmap = toBitmap(drawable, SIZE)
                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                out[pkg] = Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
                bitmap.recycle()
            } catch (t: Throwable) {
                // 这个 App 取不到图标就算了，界面用默认图标。
            }
        }
        return out
    }

    private fun toBitmap(drawable: Drawable, size: Int): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bitmap
    }
}
