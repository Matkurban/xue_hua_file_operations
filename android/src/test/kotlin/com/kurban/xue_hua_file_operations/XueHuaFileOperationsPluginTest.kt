package com.kurban.xue_hua_file_operations

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class XueHuaFileOperationsPluginTest {
    @Test
    fun onMethodCall_unknownMethod_returnsNotImplemented() {
        val plugin = XueHuaFileOperationsPlugin()

        val call = MethodCall("unknownMethod", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).notImplemented()
    }

    @Test
    fun onMethodCall_saveToGallery_missingSource_returnsInvalidArgs() {
        val plugin = XueHuaFileOperationsPlugin()
        val call = MethodCall(
            "saveToGallery",
            mapOf("fileName" to "a.jpg", "type" to "image")
        )
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        Mockito.verify(mockResult).error(
            Mockito.eq("invalid_args"),
            Mockito.anyString(),
            Mockito.isNull(),
        )
    }

    @Test
    fun onMethodCall_galleryPermissionStatus_returnsWireName() {
        val plugin = XueHuaFileOperationsPlugin()
        val call = MethodCall("galleryPermissionStatus", mapOf("forAlbum" to false))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        Mockito.verify(mockResult).success(Mockito.anyString())
    }
}
