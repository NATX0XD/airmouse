package expo.modules.airmousehid

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class AirMouseHidModule : Module() {
  private var hid: BluetoothHidDevice? = null
  private var connected: BluetoothDevice? = null
  private var pending: Promise? = null

  private val callback = object : BluetoothHidDevice.Callback() {
    override fun onAppStatusChanged(device: BluetoothDevice?, registered: Boolean) {
      if (registered) pending?.resolve(null) else pending?.reject("REGISTER_FAILED", "Bluetooth HID registerApp ไม่สำเร็จ ลองใช้ดองเกิล BLE แทน", null)
      pending = null
    }
    override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
      if (state == BluetoothProfile.STATE_CONNECTED) connected = device
      if (state == BluetoothProfile.STATE_DISCONNECTED && connected?.address == device?.address) connected = null
      if (device != null) sendEvent("onStateChange", mapOf("address" to device.address, "state" to state))
    }
  }

  override fun definition() = ModuleDefinition {
    Name("AirMouseHid")
    Events("onStateChange")
    Function("isSupported") { Build.VERSION.SDK_INT >= 28 && bluetoothAdapter()?.isEnabled == true }
    AsyncFunction("register") { promise: Promise ->
      val adapter = bluetoothAdapter()
      if (Build.VERSION.SDK_INT < 28 || adapter == null) { promise.reject("UNSUPPORTED", "เครื่องนี้ไม่รองรับ Bluetooth HID", null); return@AsyncFunction }
      pending = promise
      adapter.getProfileProxy(requireContext(), object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
          hid = proxy as BluetoothHidDevice
          val descriptor = byteArrayOf(
            0x05, 0x01, 0x09, 0x06, 0xA1.toByte(), 0x01,
            0x85.toByte(), 0x01, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, 0x95.toByte(), 0x03, 0x75, 0x01, 0x81.toByte(), 0x02,
            0x95.toByte(), 0x01, 0x75, 0x05, 0x81.toByte(), 0x01, 0x95.toByte(), 0x03, 0x75, 0x08, 0x15, 0x81.toByte(), 0x25, 0x7F, 0x81.toByte(), 0x06,
            0xC0.toByte(),
            0x05, 0x01, 0x09, 0x06, 0xA1.toByte(), 0x01, 0x85.toByte(), 0x02, 0x05, 0x07, 0x19, 0xE0.toByte(), 0x29, 0xE7.toByte(), 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95.toByte(), 0x08, 0x81.toByte(), 0x02, 0x95.toByte(), 0x01, 0x75, 0x08, 0x81.toByte(), 0x01, 0xC0.toByte()
          )
          hid?.registerApp(
            BluetoothHidDeviceAppSdpSettings("AirMouse", "AirMouse", "AirMouse", BluetoothHidDevice.SUBCLASS1_MOUSE, descriptor),
            null, null, requireContext().mainExecutor, callback
          )
        }
        override fun onServiceDisconnected(profile: Int) { hid = null }
      }, BluetoothProfile.HID_DEVICE)
    }
    Function("getBondedDevices") {
      bluetoothAdapter()?.bondedDevices?.map { mapOf("address" to it.address, "name" to it.name) } ?: emptyList<Map<String, String?>>()
    }
    AsyncFunction("connect") { address: String, promise: Promise ->
      val device = bluetoothAdapter()?.getRemoteDevice(address)
      if (device == null || hid?.connect(device) != true) promise.reject("CONNECT_FAILED", "เชื่อมต่อ Bluetooth HID ไม่สำเร็จ ลองใช้ดองเกิล BLE แทน", null) else promise.resolve(null)
    }
    AsyncFunction("disconnect") { promise: Promise ->
      val device = connected
      if (device != null) hid?.disconnect(device)
      promise.resolve(null)
    }
    AsyncFunction("send") { report: List<Int>, promise: Promise ->
      val device = connected
      val profile = hid
      if (device == null || profile == null || report.size < 5) { promise.resolve(false); return@AsyncFunction }
      val mouse = byteArrayOf(report[0].toByte(), report[1].toByte(), report[2].toByte(), report[3].toByte())
      var ok = profile.sendReport(device, 1, mouse)
      val key = report[4]
      if (key != 0) {
        val keyboard = ByteArray(8)
        keyboard[2] = if (key == 1) 0x50 else 0x4F
        ok = profile.sendReport(device, 2, keyboard) && ok
        ok = profile.sendReport(device, 2, ByteArray(8)) && ok
      }
      promise.resolve(ok)
    }
  }

  private fun requireContext(): Context = appContext.reactContext ?: throw IllegalStateException("Context unavailable")
  private fun bluetoothAdapter(): BluetoothAdapter? = (requireContext().getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager)?.adapter
}
