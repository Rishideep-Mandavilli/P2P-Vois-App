// Vois native Android radio transport plugin
package com.vois.p2p

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android WiFi Direct (WiFi P2P) transport — the mandated *primary*
 * transport (Section 5), with Bluetooth Classic (P2pServerPlugin) kept as
 * the automatic fallback. Deliberately built on raw AOSP WifiP2pManager
 * APIs, not Google's Nearby Connections (which depends on Play Services —
 * the PS bans closed-source/proprietary SDKs for this path).
 *
 * WiFi P2P only negotiates *link* connectivity (who's group owner, and the
 * resulting local IP addresses); actual data transfer still needs a plain
 * TCP socket over that link, which is what the accept-loop/connect/read/
 * write plumbing below does — deliberately mirroring P2pServerPlugin.kt's
 * shape (id -> socket map, background read threads, main-thread event
 * emission) so both transports present the same connection-id model to
 * the Dart side.
 */
class WifiDirectPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    companion object {
        const val CHANNEL = "p2p_wifi/methods"
        const val EVENTS = "p2p_wifi/events"
        const val TCP_PORT = 8988
        private const val PERMISSION_REQUEST = 4001
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var channel: MethodChannel? = null
    private var events: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var permissionListener: PluginRegistry.RequestPermissionsResultListener? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var manager: WifiP2pManager? = null
    private var p2pChannel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var isGroupOwner = false

    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private val connections = ConcurrentHashMap<Int, Socket>()
    private val nextConnectionId = AtomicInteger(1)
    private val writeExecutor = Executors.newSingleThreadExecutor()
    private val pendingAudioFrames = ConcurrentHashMap<Int, AtomicInteger>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, EVENTS).also {
            it.setStreamHandler(this)
        }
        manager = binding.applicationContext.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        p2pChannel = manager?.initialize(binding.applicationContext, Looper.getMainLooper(), null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopServer()
        unregisterReceiver()
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
            if (requestCode == PERMISSION_REQUEST) {
                val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
                true
            } else {
                false
            }
        }
        binding.addRequestPermissionsResultListener(permissionListener!!)
    }

    override fun onDetachedFromActivity() {
        permissionListener?.let { activityBinding?.removeRequestPermissionsResultListener(it) }
        permissionListener = null
        pendingPermissionResult = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        permissionListener?.let { activityBinding?.removeRequestPermissionsResultListener(it) }
        permissionListener = null
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "discoverPeers" -> {
                discoverPeers()
                result.success(true)
            }
            "stopDiscovery" -> {
                manager?.stopPeerDiscovery(p2pChannel, null)
                result.success(true)
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("bad_argument", "address required", null)
                } else {
                    connectPeer(address, result)
                }
            }
            "createGroup" -> {
                manager?.createGroup(p2pChannel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { mainHandler.post { result.success(true) } }
                    override fun onFailure(reason: Int) { mainHandler.post { result.error("group_error", "reason=$reason", null) } }
                })
            }
            "removeGroup" -> {
                manager?.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { mainHandler.post { result.success(true) } }
                    override fun onFailure(reason: Int) { mainHandler.post { result.success(false) } }
                })
                stopServer()
            }
            "write" -> writeConnection(call, result)
            "close" -> {
                val id = call.argument<Int>("id") ?: -1
                pendingAudioFrames.remove(id)
                connections.remove(id)?.let {
                    try { it.close() } catch (_: Exception) {}
                }
                result.success(true)
            }
            "stop" -> {
                stopServer()
                unregisterReceiver()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ---- Permissions ---------------------------------------------------------

    private fun requestPermissions(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33) {
            needed.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val missing = needed.filter {
            ContextCompat.checkSelfPermission(applicationContext!!, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty() || activity == null) {
            result.success(missing.isEmpty())
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), PERMISSION_REQUEST)
    }

    // ---- Discovery / connection -----------------------------------------------

    private fun registerReceiver() {
        if (receiver != null) return
        val context = applicationContext ?: return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        manager?.requestPeers(p2pChannel) { peers: WifiP2pDeviceList ->
                            emit(mapOf(
                                "event" to "peers",
                                "peers" to peers.deviceList.map {
                                    mapOf(
                                        "name" to (it.deviceName ?: ""),
                                        "address" to it.deviceAddress,
                                        "status" to it.status,
                                    )
                                },
                            ))
                        }
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        manager?.requestConnectionInfo(p2pChannel) { info: WifiP2pInfo ->
                            if (info.groupFormed) {
                                onGroupFormed(info)
                            }
                        }
                    }
                }
            }
        }
        context.registerReceiver(r, IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        })
        receiver = r
    }

    private fun unregisterReceiver() {
        try {
            receiver?.let { applicationContext?.unregisterReceiver(it) }
        } catch (_: Exception) {
        }
        receiver = null
    }

    private fun discoverPeers() {
        registerReceiver()
        manager?.discoverPeers(p2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {}
            override fun onFailure(reason: Int) {
                emit(mapOf("event" to "error", "message" to "discover failed: $reason"))
            }
        })
    }

    private fun connectPeer(address: String, result: MethodChannel.Result) {
        registerReceiver()
        val config = WifiP2pConfig().apply { deviceAddress = address }
        manager?.connect(p2pChannel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() { mainHandler.post { result.success(true) } }
            override fun onFailure(reason: Int) { mainHandler.post { result.error("connect_error", "reason=$reason", null) } }
        })
    }

    /// Called once WifiP2pManager reports the link is up. The group owner
    /// runs a TCP server socket; every other member connects a TCP client
    /// socket to it. This is what makes group-owner mode double as the
    /// one-to-many broadcast transport — every client that
    /// connects becomes its own entry in [connections], so a send to "all"
    /// is just a write to every id in that map.
    private fun onGroupFormed(info: WifiP2pInfo) {
        isGroupOwner = info.isGroupOwner
        if (info.isGroupOwner) {
            startServer()
            emit(mapOf("event" to "group_formed", "isGroupOwner" to true))
        } else {
            val hostAddress = info.groupOwnerAddress?.hostAddress
            if (hostAddress != null) {
                connectToHost(hostAddress)
            }
            emit(mapOf("event" to "group_formed", "isGroupOwner" to false, "groupOwnerAddress" to hostAddress))
        }
    }

    // ---- TCP transport ---------------------------------------------------------

    private fun startServer() {
        stopServer()
        val socket = try {
            ServerSocket(TCP_PORT)
        } catch (e: Exception) {
            emit(mapOf("event" to "error", "message" to e.message))
            return
        }
        serverSocket = socket
        acceptThread = Thread {
            while (!Thread.currentThread().isInterrupted) {
                val accepted = try {
                    socket.accept()
                } catch (_: Exception) {
                    break
                }
                val id = nextConnectionId.getAndIncrement()
                connections[id] = accepted
                emit(mapOf(
                    "event" to "accepted",
                    "id" to id,
                    "address" to accepted.inetAddress?.hostAddress,
                ))
                startReadLoop(id, accepted)
            }
        }
        acceptThread?.start()
    }

    private fun connectToHost(hostAddress: String) {
        Thread {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(hostAddress, TCP_PORT), 10_000)
                val id = nextConnectionId.getAndIncrement()
                connections[id] = socket
                emit(mapOf("event" to "client_connected", "id" to id, "address" to hostAddress))
                startReadLoop(id, socket)
            } catch (e: Exception) {
                emit(mapOf("event" to "error", "message" to e.message))
            }
        }.start()
    }

    private fun stopServer() {
        acceptThread?.interrupt()
        acceptThread = null
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        for ((_, socket) in connections) {
            try { socket.close() } catch (_: Exception) {}
        }
        connections.clear()
    }

    private fun startReadLoop(id: Int, socket: Socket) {
        Thread {
            try {
                val input = socket.getInputStream()
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

        val isAudio = bytes.isNotEmpty() && bytes[0] == 1.toByte()
        if (isAudio) {
            val audioCount = pendingAudioFrames.getOrPut(id) { AtomicInteger(0) }
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
                    sock.getOutputStream().write(bytes)
                    sock.getOutputStream().flush()
                }
            } catch (e: Exception) {
                pendingAudioFrames.remove(id)
                connections.remove(id)
                try { sock.close() } catch (_: Exception) {}
                emit(mapOf("event" to "closed", "id" to id))
            } finally {
                if (isAudio) {
                    pendingAudioFrames[id]?.decrementAndGet()
                }
            }
        }
    }

    // ---- Events -------------------------------------------------------------

    private fun emit(payload: Map<String, Any?>) {
        val sink = eventSink
        if (sink == null) return
        mainHandler.post { sink.success(payload) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
