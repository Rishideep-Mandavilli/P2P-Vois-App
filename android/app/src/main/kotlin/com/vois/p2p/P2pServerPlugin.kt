// Vois native Android radio transport plugin
package com.vois.p2p

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Full RFCOMM transport for the P2P walkie: server accept, client connect,
 * discovery, bonding (with auto-accept pairing), discoverable mode, and the
 * foreground service keep-alive.
 *
 * Rule that keeps the app alive: every MethodChannel reply and EventChannel
 * emission happens on the main thread. Socket I/O runs on background threads.
 */
class P2pServerPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    companion object {
        const val SPP_UUID = "00001101-0000-1000-8000-00805F9B34FB"
        const val CHANNEL = "p2p_server/methods"
        const val EVENTS = "p2p_server/events"
        private const val FGS_PERMISSION_REQUEST = 3001
        private const val DISCOVERABLE_REQUEST = 3002
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var channel: MethodChannel? = null
    private var events: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var permissionListener: PluginRegistry.RequestPermissionsResultListener? = null
    private var activityResultListener: PluginRegistry.ActivityResultListener? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDiscoverableResult: MethodChannel.Result? = null

    // Server accept state.
    private var acceptThread: Thread? = null
    private var serverSocket: BluetoothServerSocket? = null

    // Client / accepted connections: id -> socket.
    private val connections = ConcurrentHashMap<Int, BluetoothSocket>()
    private val nextConnectionId = AtomicInteger(1)

    // Track connection count per remote address for TX/RX role assignment.
    private val connectionCountPerAddress = ConcurrentHashMap<String, AtomicInteger>()
    // Reverse map: connection id -> remote address (for cleanup on close).
    private val connectionAddress = ConcurrentHashMap<Int, String>()

    // Background write executor and pending write tracking for anti-bufferbloat.
    private val writeExecutor = Executors.newSingleThreadExecutor()
    private val pendingAudioFrames = ConcurrentHashMap<Int, AtomicInteger>()


    // Discovery + bonding.
    private var discoveryReceiver: BroadcastReceiver? = null
    private var bondReceiver: BroadcastReceiver? = null
    private var scanning = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, EVENTS).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopListening()
        stopAlertTone()
        unregisterReceivers()
        try { writeExecutor.shutdownNow() } catch (_: Exception) {}
        channel?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        channel = null
        events = null
        eventSink = null
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        permissionListener = PluginRegistry.RequestPermissionsResultListener { requestCode, _, grantResults ->
            if (requestCode == FGS_PERMISSION_REQUEST) {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) startRadioService()
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
                true
            } else {
                false
            }
        }
        binding.addRequestPermissionsResultListener(permissionListener!!)
        activityResultListener = PluginRegistry.ActivityResultListener { requestCode, _, data ->
            if (requestCode == DISCOVERABLE_REQUEST) {
                val seconds = data?.getIntExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 0) ?: 0
                pendingDiscoverableResult?.success(seconds > 0)
                pendingDiscoverableResult = null
                true
            } else {
                false
            }
        }
        binding.addActivityResultListener(activityResultListener!!)
    }

    override fun onDetachedFromActivity() {
        permissionListener?.let { activityBinding?.removeRequestPermissionsResultListener(it) }
        activityResultListener?.let { activityBinding?.removeActivityResultListener(it) }
        permissionListener = null
        activityResultListener = null
        pendingPermissionResult = null
        pendingDiscoverableResult = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        permissionListener?.let { activityBinding?.removeRequestPermissionsResultListener(it) }
        activityResultListener?.let { activityBinding?.removeActivityResultListener(it) }
        permissionListener = null
        activityResultListener = null
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensureRadioService" -> ensureRadioService(result)
            "requestEnable" -> {
                requestEnable()
                result.success(true)
            }
            "requestDiscoverable" -> requestDiscoverable(result, call.argument<Int>("seconds") ?: 120)
            "getName" -> result.success(bluetoothAdapter()?.name ?: "")
            "getBondedDevices" -> result.success(bondedDevicesList())
            "isBonded" -> {
                val address = call.argument<String>("address")
                val bonded = address?.let { bluetoothAdapter()?.getRemoteDevice(it)?.bondState == BluetoothDevice.BOND_BONDED }
                result.success(bonded)
            }
            "startDiscovery" -> {
                startDiscovery()
                result.success(true)
            }
            "cancelDiscovery" -> {
                cancelDiscovery()
                result.success(true)
            }
            "bond" -> {
                val address = call.argument<String>("address")
                bondDevice(address)
                result.success(true)
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("bad_argument", "address required", null)
                } else {
                    connectClient(address, result)
                }
            }
            "connectDual" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("bad_argument", "address required", null)
                } else {
                    connectDual(address, result)
                }
            }
            "write" -> writeConnection(call, result)
            "close" -> {
                val id = call.argument<Int>("id") ?: -1
                pendingAudioFrames.remove(id)
                connections.remove(id)?.let {
                    try { it.close() } catch (_: Exception) {}
                }
                connectionAddress.remove(id)
                result.success(true)
            }
            "startListening" -> {
                startListening()
                result.success(true)
            }
            "stop" -> {
                stopListening()
                result.success(true)
            }
            "getLastKnownLocation" -> result.success(lastKnownLocation())
            "getBatteryLevel" -> result.success(batteryLevelPercent())
            "setMaxAlertVolume" -> {
                setMaxAlertVolume()
                result.success(true)
            }
            "vibrateAlert" -> {
                vibrateAlert()
                result.success(true)
            }
            "playAlertTone" -> {
                playAlertTone(call.argument<Int>("ms") ?: 6000)
                result.success(true)
            }
            "stopAlertTone" -> {
                stopAlertTone()
                result.success(true)
            }
            "setEarpiece" -> {
                val ok = setEarpiece()
                result.success(ok)
            }
            "setLoudspeaker" -> {
                val ok = setLoudspeaker()
                result.success(ok)
            }
            "resetAudioMode" -> {
                resetAudioMode()
                result.success(true)
            }
            "isEarpieceAvailable" -> {
                result.success(isEarpieceAvailable())
            }
            else -> result.notImplemented()
        }
    }

    // ---- Foreground service ------------------------------------------------

    private fun ensureRadioService(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 34) {
            startRadioService()
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startRadioService()
            result.success(true)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE),
            FGS_PERMISSION_REQUEST,
        )
    }

    private fun startRadioService() {
        val activity = activityBinding?.activity ?: return
        try {
            val intent = Intent(activity, RadioService::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
        } catch (_: Exception) {
            // Never crash the app if the service can't start.
        }
    }

    // ---- Adapter helpers ----------------------------------------------------

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val ctx = activityBinding?.activity ?: applicationContext ?: return null
        return if (Build.VERSION.SDK_INT >= 31) {
            ctx.getSystemService(BluetoothManager::class.java)?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun requestEnable() {
        val activity = activityBinding?.activity ?: return
        try {
            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            activity.startActivityForResult(intent, 0)
        } catch (_: Exception) {
        }
    }

    private fun requestDiscoverable(result: MethodChannel.Result, seconds: Int) {
        val activity = activityBinding?.activity ?: run {
            result.success(false)
            return
        }
        pendingDiscoverableResult = result
        try {
            val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, seconds)
            activity.startActivityForResult(intent, DISCOVERABLE_REQUEST)
        } catch (e: Exception) {
            pendingDiscoverableResult = null
            result.success(false)
        }
    }

    // ---- Discovery ----------------------------------------------------------

    private fun bondedDevicesList(): List<Map<String, Any?>> {
        val adapter = bluetoothAdapter() ?: return emptyList()
        return adapter.bondedDevices.map { d ->
            mapOf(
                "name" to (d.name ?: ""),
                "address" to d.address,
                "bondState" to d.bondState,
            )
        }
    }

    private fun registerDiscoveryReceiver() {
        if (discoveryReceiver != null) return
        val context = applicationContext ?: return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, -100)
                        device?.let {
                            emit(
                                mapOf(
                                    "event" to "scan_found",
                                    "name" to (it.name ?: ""),
                                    "address" to it.address,
                                    "bondState" to it.bondState,
                                    "rssi" to rssi.toInt(),
                                )
                            )
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        emit(mapOf("event" to "scan_finished"))
                        scanning = false
                    }
                }
            }
        }
        context.registerReceiver(receiver, IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        })
        discoveryReceiver = receiver
    }

    private fun startDiscovery() {
        val adapter = bluetoothAdapter() ?: return
        if (scanning || adapter.isDiscovering) return
        registerDiscoveryReceiver()
        scanning = adapter.startDiscovery()
    }

    private fun cancelDiscovery() {
        try {
            bluetoothAdapter()?.cancelDiscovery()
        } catch (_: Exception) {
        }
        scanning = false
    }

    // ---- Bonding / pairing auto-accept --------------------------------------

    private fun registerBondReceiver() {
        if (bondReceiver != null) return
        val context = applicationContext ?: return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        device?.let {
                            try {
                                it.setPairingConfirmation(true)
                                it.setPin("0000".toByteArray())
                            } catch (_: Exception) {
                            }
                        }
                    }
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        device?.let {
                            emit(
                                mapOf(
                                    "event" to "bond_state",
                                    "address" to it.address,
                                    "bondState" to it.bondState,
                                )
                            )
                        }
                    }
                }
            }
        }
        context.registerReceiver(receiver, IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        })
        bondReceiver = receiver
    }

    private fun bondDevice(address: String?) {
        if (address == null) return
        val adapter = bluetoothAdapter() ?: return
        registerBondReceiver()
        try {
            val device = adapter.getRemoteDevice(address)
            if (device.bondState != BluetoothDevice.BOND_BONDED) {
                device.createBond()
            }
        } catch (_: Exception) {
        }
    }

    private fun unregisterReceivers() {
        try {
            val context = applicationContext ?: return
            discoveryReceiver?.let { context.unregisterReceiver(it) }
            bondReceiver?.let { context.unregisterReceiver(it) }
        } catch (_: Exception) {
        }
        discoveryReceiver = null
        bondReceiver = null
    }

    // ---- Server accept ------------------------------------------------------

    private fun startListening() {
        stopListening()
        val adapter = bluetoothAdapter() ?: return
        if (!adapter.isEnabled) return
        val socket = try {
            adapter.listenUsingRfcommWithServiceRecord("P2PWalkie", UUID.fromString(SPP_UUID))
        } catch (e: Exception) {
            emit(mapOf("event" to "error", "message" to e.message))
            return
        }
        serverSocket = socket
        acceptThread = Thread {
            while (!Thread.currentThread().isInterrupted) {
                val accepted = try {
                    socket.accept()
                } catch (e: Exception) {
                    if (serverSocket == null || Thread.currentThread().isInterrupted) break
                    try { Thread.sleep(300) } catch (_: InterruptedException) { break }
                    continue
                }
                val id = nextConnectionId.getAndIncrement()
                connections[id] = accepted
                val addr = accepted.remoteDevice?.address ?: ""
                connectionAddress[id] = addr
                val count = connectionCountPerAddress.getOrPut(addr) { AtomicInteger(0) }
                val role = if (count.incrementAndGet() == 1) "rx" else "tx"
                emit(mapOf("event" to "accepted", "id" to id, "address" to addr, "role" to role))
                startReadLoop(id, accepted)
            }
        }
        acceptThread?.start()
    }

    private fun stopListening() {
        acceptThread?.interrupt()
        acceptThread = null
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
    }

    // ---- Client connect -----------------------------------------------------

    private fun connectClient(address: String, result: MethodChannel.Result) {
        Thread {
            var socket: BluetoothSocket? = null
            try {
                val adapter = bluetoothAdapter()
                    ?: throw IOException("bluetooth unavailable")
                cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                
                var lastError: Exception? = null
                var connected = false

                // Try secure RFCOMM first with retry
                for (attempt in 1..3) {
                    try {
                        cancelDiscovery()
                        socket = device.createRfcommSocketToServiceRecord(UUID.fromString(SPP_UUID))
                        socket.connect()
                        connected = true
                        break
                    } catch (e: Exception) {
                        lastError = e
                        try { socket?.close() } catch (_: Exception) {}
                        socket = null
                        if (attempt < 3) {
                            try { Thread.sleep(300) } catch (_: InterruptedException) { break }
                        }
                    }
                }

                if (!connected) {
                    // Fallback to insecure RFCOMM socket
                    try {
                        cancelDiscovery()
                        socket = device.createInsecureRfcommSocketToServiceRecord(UUID.fromString(SPP_UUID))
                        socket.connect()
                        connected = true
                    } catch (e: Exception) {
                        lastError = e
                        try { socket?.close() } catch (_: Exception) {}
                        socket = null
                    }
                }

                if (!connected || socket == null) {
                    throw lastError ?: IOException("connect failed")
                }

                val id = nextConnectionId.getAndIncrement()
                connections[id] = socket
                connectionAddress[id] = address
                emit(mapOf("event" to "client_connected", "id" to id, "address" to address))
                startReadLoop(id, socket)
                val okId = id
                mainHandler.post { result.success(okId) }
            } catch (e: Exception) {
                try { socket?.close() } catch (_: Exception) {}
                val msg = e.message
                mainHandler.post { result.error("connect_error", msg, null) }
            }
        }.start()
    }

    private fun connectDual(address: String, result: MethodChannel.Result) {
        Thread {
            val ids = mutableListOf<Int>()
            val sockets = mutableListOf<BluetoothSocket>()
            try {
                val adapter = bluetoothAdapter()
                    ?: throw IOException("bluetooth unavailable")
                val device = adapter.getRemoteDevice(address)
                for (i in 1..2) {
                    var connected = false
                    var lastError: Exception? = null
                    for (attempt in 1..3) {
                        try {
                            val socket = device.createRfcommSocketToServiceRecord(UUID.fromString(SPP_UUID))
                            socket.connect()
                            sockets.add(socket)
                            val id = nextConnectionId.getAndIncrement()
                            connections[id] = socket
                            connectionAddress[id] = address
                            ids.add(id)
                            connected = true
                            break
                        } catch (e: Exception) {
                            lastError = e
                            if (attempt < 3) Thread.sleep(300)
                        }
                    }
                    if (!connected) throw lastError ?: IOException("connect failed")
                    emit(mapOf("event" to "client_connected", "id" to ids.last(), "address" to address, "role" to if (i == 1) "tx" else "rx"))
                    startReadLoop(ids.last(), sockets.last())
                    if (i == 1) Thread.sleep(200)
                }
                val txId = ids[0]
                val rxId = ids[1]
                mainHandler.post { result.success(mapOf("txId" to txId, "rxId" to rxId)) }
            } catch (e: Exception) {
                ids.forEach { id ->
                    connections.remove(id)
                    connectionAddress.remove(id)
                }
                sockets.forEach { try { it.close() } catch (_: Exception) {} }
                val msg = e.message
                mainHandler.post { result.error("connect_error", msg, null) }
            }
        }.start()
    }

    // ---- Read / write -------------------------------------------------------

    private fun startReadLoop(id: Int, socket: BluetoothSocket) {
        Thread {
            try {
                val input = socket.inputStream
                val buffer = ByteArray(4096)
                while (!Thread.currentThread().isInterrupted) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    val chunk = ByteArray(read)
                    System.arraycopy(buffer, 0, chunk, 0, read)
                    emit(mapOf("event" to "data", "id" to id, "bytes" to chunk))
                }
            } catch (_: Exception) {
            } finally {
                pendingAudioFrames.remove(id)
                connections.remove(id)
                val addr = connectionAddress.remove(id)
                if (addr != null) {
                    val counter = connectionCountPerAddress[addr]
                    if (counter != null && counter.decrementAndGet() <= 0) {
                        connectionCountPerAddress.remove(addr)
                    }
                }
                try { socket.close() } catch (_: Exception) {}
                emit(mapOf("event" to "closed", "id" to id))
            }
        }.start()
    }

    private fun writeConnection(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id") ?: -1
        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
        val sock = connections[id]
        if (sock == null || !sock.isConnected) {
            result.error("write_error", "connection $id not open", null)
            return
        }

        // FrameType: 0x01 is audio frame.
        val isAudio = bytes.isNotEmpty() && bytes[0] == 1.toByte()

        if (isAudio) {
            val audioCount = pendingAudioFrames.getOrPut(id) { AtomicInteger(0) }
            // If 2 or more audio frames are already queued in flight, drop the
            // older frame to prevent bufferbloat and guarantee real-time latency (<40ms).
            if (audioCount.get() >= 2) {
                result.success(true)
                return
            }
            audioCount.incrementAndGet()
        }

        result.success(true)

        writeExecutor.execute {
            try {
                if (sock.isConnected) {
                    sock.outputStream.write(bytes)
                    sock.outputStream.flush()
                }
            } catch (e: Exception) {
                connections.remove(id)
                val addr = connectionAddress.remove(id)
                if (addr != null) {
                    val counter = connectionCountPerAddress[addr]
                    if (counter != null && counter.decrementAndGet() <= 0) {
                        connectionCountPerAddress.remove(addr)
                    }
                }
                pendingAudioFrames.remove(id)
                try { sock.close() } catch (_: Exception) {}
                emit(mapOf("event" to "closed", "id" to id))
            } finally {
                if (isAudio) {
                    pendingAudioFrames[id]?.decrementAndGet()
                }
            }
        }
    }

    // ---- Adaptive duty-cycling -------------------------------

    private fun batteryLevelPercent(): Int? {
        val ctx = activityBinding?.activity ?: applicationContext ?: return null
        return try {
            val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } catch (_: Exception) {
            null
        }
    }

    // ---- Alerts --------------------------------------

    /// Plain android.location.LocationManager — deliberately not Play
    /// Services' FusedLocationProvider, to keep the SOS/GPS path on the
    /// same "no proprietary SDK" footing as the WiFi Direct transport
    /// choice. Only returns whatever the device already has cached from
    /// its GPS chip; never triggers a network location lookup.
    @Suppress("DEPRECATION")
    private fun lastKnownLocation(): Map<String, Any?>? {
        val ctx = activityBinding?.activity ?: applicationContext ?: return null
        val hasFine = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val hasCoarse = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) return null
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        var best: android.location.Location? = null
        for (provider in providers) {
            try {
                val loc = lm.getLastKnownLocation(provider) ?: continue
                if (best == null || loc.time > best!!.time) best = loc
            } catch (_: Exception) {
            }
        }
        val loc = best ?: return null
        return mapOf("lat" to loc.latitude, "lng" to loc.longitude, "timestamp" to loc.time)
    }

    /// Alert-type messages must play at max volume and be as hard to miss
    /// as possible. We push both the media stream (what
    /// flutter_sound's audio playback uses) and the alarm stream to max —
    /// the alarm stream in particular is the one Android generally does
    /// NOT silence under Do Not Disturb, unlike notifications/ringer.
    private fun setMaxAlertVolume() {
        val ctx = activityBinding?.activity ?: applicationContext ?: return
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            am.setStreamVolume(AudioManager.STREAM_MUSIC, am.getStreamMaxVolume(AudioManager.STREAM_MUSIC), 0)
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (_: Exception) {
        }
    }

    /// Haptic companion to an incoming alert — vibration
    /// is not silenced by most Do Not Disturb configurations (aside from
    /// "Total silence"), so it's a second, more reliable attention channel
    /// alongside the audio.
    private fun vibrateAlert() {
        val ctx = activityBinding?.activity ?: applicationContext ?: return
        try {
            val pattern = longArrayOf(0, 400, 200, 400, 200, 400)
            if (Build.VERSION.SDK_INT >= 31) {
                val vm = ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= 26) {
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(pattern, -1)
                }
            }
        } catch (_: Exception) {
        }
    }

    private var alertTone: ToneGenerator? = null
    private var alertToneHandler: Handler? = null

    /// The audio half of an incoming SOS. A phone lying face-down keeps no
    /// screen up, so a banner alone reaches nobody — this beeps a repeating
    /// two-tone pattern on the alarm stream, which Android generally does not
    /// silence under Do Not Disturb. Generated rather than a ringtone file so
    /// it still works on a device with no user sounds installed.
    private fun playAlertTone(durationMs: Int) {
        stopAlertTone()
        val generator = try {
            ToneGenerator(AudioManager.STREAM_ALARM, 100)
        } catch (_: Exception) {
            return
        }
        alertTone = generator
        val handler = Handler(Looper.getMainLooper())
        alertToneHandler = handler
        var high = true
        val pulse = object : Runnable {
            override fun run() {
                val current = alertTone ?: return
                current.startTone(
                    if (high) ToneGenerator.TONE_PROP_BEEP else ToneGenerator.TONE_PROP_BEEP2,
                    320,
                )
                high = !high
                handler.postDelayed(this, 420)
            }
        }
        handler.post(pulse)
        handler.postDelayed({ stopAlertTone() }, durationMs.toLong())
    }

    private fun stopAlertTone() {
        alertToneHandler?.removeCallbacksAndMessages(null)
        alertToneHandler = null
        try {
            alertTone?.release()
        } catch (_: Exception) {
        }
        alertTone = null
    }

    // ---- Audio routing & Proximity ------------------------------------------

    private var proximityWakeLock: PowerManager.WakeLock? = null

    private fun audioManager(): AudioManager? {
        val ctx = activityBinding?.activity ?: applicationContext ?: return null
        return ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    private fun acquireProximityLock() {
        try {
            val ctx = activityBinding?.activity ?: applicationContext ?: return
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                    if (proximityWakeLock == null) {
                        proximityWakeLock = pm.newWakeLock(
                            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                            "vois:proximity"
                        )
                    }
                    if (proximityWakeLock?.isHeld == false) {
                        proximityWakeLock?.acquire(3600000L) // 1 hour max safety timeout
                    }
                }
            }
        } catch (_: Exception) {}
    }

    private fun releaseProximityLock() {
        try {
            if (proximityWakeLock?.isHeld == true) {
                proximityWakeLock?.release()
            }
        } catch (_: Exception) {}
    }

    private fun isEarpieceAvailable(): Boolean {
        val am = audioManager() ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            am.availableCommunicationDevices.any { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
        } else {
            val ctx = applicationContext ?: return false
            ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
        }
    }

    private fun setEarpiece(): Boolean {
        val am = audioManager() ?: return false
        return try {
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            var routed = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                val earpiece = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                if (earpiece != null) {
                    routed = am.setCommunicationDevice(earpiece)
                }
            }
            if (!routed) {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = false
            }
            acquireProximityLock()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun setLoudspeaker(): Boolean {
        val am = audioManager() ?: return false
        return try {
            releaseProximityLock()
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            var routed = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = am.availableCommunicationDevices
                val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (speaker != null) {
                    routed = am.setCommunicationDevice(speaker)
                } else {
                    am.clearCommunicationDevice()
                }
            }
            if (!routed) {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = true
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun resetAudioMode() {
        releaseProximityLock()
        val am = audioManager() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.clearCommunicationDevice()
            }
            @Suppress("DEPRECATION")
            am.isSpeakerphoneOn = false
            am.mode = AudioManager.MODE_NORMAL
        } catch (_: Exception) {}
    }

    // ---- Events -------------------------------------------------------------

    private fun emit(payload: Map<String, Any?>) {
        val sink = eventSink
        if (sink == null) return
        mainHandler.post { sink.success(payload) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        registerBondReceiver()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
