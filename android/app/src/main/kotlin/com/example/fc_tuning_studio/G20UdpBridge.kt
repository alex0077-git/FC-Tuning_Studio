package com.example.fc_tuning_studio

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * G20 UDP uplink fix pass:
 * - IO thread for all socket ops (main-thread send was tx=0)
 * - Probe whether anything is bound on :14552 (QGC target)
 * - Bind RX on 127.0.0.1:listen first (source addr = loopback for TX)
 * - connect() UDP to target before send (matches many GCS stacks)
 */
class G20UdpBridge(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val method = MethodChannel(messenger, "fc_tuning_studio/g20_udp")
    private val events = EventChannel(messenger, "fc_tuning_studio/g20_udp_rx")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { r ->
        Thread(r, "g20-udp-io").also { it.isDaemon = true }
    }

    private var socket: DatagramSocket? = null
    private var configuredTarget: InetSocketAddress? = null
    private var sink: EventChannel.EventSink? = null
    private val running = AtomicBoolean(false)
    private var rxThread: Thread? = null

    private val rxBytes = AtomicLong(0)
    private val txBytes = AtomicLong(0)
    private val rxPkts = AtomicInteger(0)
    private val txPkts = AtomicInteger(0)
    private val txFail = AtomicInteger(0)
    private val lastTxError = AtomicReference("")
    private val targetListenState = AtomicReference("?") // free | busy | err
    private var bindMode = "—"
    private val learnedPeer = AtomicReference<InetSocketAddress?>(null)

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                val listen = call.argument<Int>("listenPort") ?: 14551
                val host = call.argument<String>("targetHost") ?: "127.0.0.1"
                val port = call.argument<Int>("targetPort") ?: 14552
                io.execute {
                    try {
                        open(listen, host, port)
                        main.post {
                            result.success(
                                mapOf(
                                    "bindMode" to bindMode,
                                    "listenPort" to listen,
                                    "target" to "$host:$port",
                                    "targetListen" to targetListenState.get(),
                                ),
                            )
                        }
                    } catch (e: Exception) {
                        main.post {
                            result.error("open_failed", e.message, null)
                        }
                    }
                }
            }
            "send" -> {
                val data = readBytes(call.argument("data"))
                if (data == null || data.isEmpty()) {
                    result.error("bad_args", "data required", null)
                    return
                }
                io.execute {
                    val n = send(data)
                    main.post { result.success(n) }
                }
            }
            "stats" -> result.success(stats())
            "close" -> {
                io.execute {
                    closeLocked()
                    main.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** If we can bind :14552, nothing is listening — uplink target is dead. */
    private fun probeTargetPort(host: String, port: Int): String {
        return try {
            val probe = DatagramSocket(null)
            probe.reuseAddress = false
            probe.bind(InetSocketAddress(InetAddress.getByName(host), port))
            probe.close()
            "free" // BAD for uplink — nobody receiving our commands
        } catch (_: java.net.BindException) {
            "busy" // GOOD — something (mavlinkd) owns the port
        } catch (e: Exception) {
            "err:${e.javaClass.simpleName}"
        }
    }

    private fun open(listenPort: Int, targetHost: String, targetPort: Int) {
        closeLocked()
        rxBytes.set(0)
        txBytes.set(0)
        rxPkts.set(0)
        txPkts.set(0)
        txFail.set(0)
        lastTxError.set("")
        learnedPeer.set(null)

        targetListenState.set(probeTargetPort(targetHost, targetPort))

        val loopback = InetAddress.getByName("127.0.0.1")
        val sock = DatagramSocket(null)
        sock.reuseAddress = true

        // Prefer loopback bind so TX source is 127.0.0.1:listenPort (QGC-on-device).
        try {
            sock.bind(InetSocketAddress(loopback, listenPort))
            bindMode = "lo:$listenPort"
        } catch (_: Exception) {
            sock.bind(InetSocketAddress(listenPort))
            bindMode = "any:$listenPort"
        }
        sock.soTimeout = 300
        socket = sock

        val target = InetSocketAddress(InetAddress.getByName(targetHost), targetPort)
        configuredTarget = target
        // Connected UDP — some Android stacks route localhost more reliably.
        try {
            sock.connect(target)
        } catch (e: Exception) {
            lastTxError.set("connect:${e.javaClass.simpleName}")
        }

        running.set(true)
        rxThread = Thread({
            val buf = ByteArray(4096)
            while (running.get()) {
                val s = socket ?: break
                try {
                    val packet = DatagramPacket(buf, buf.size)
                    s.receive(packet)
                    if (packet.length <= 0) continue
                    // When connected, address may be the connected peer.
                    learnedPeer.set(InetSocketAddress(packet.address, packet.port))
                    val copy = packet.data.copyOf(packet.length)
                    rxBytes.addAndGet(copy.size.toLong())
                    rxPkts.incrementAndGet()
                    main.post { sink?.success(copy) }
                } catch (_: java.net.SocketTimeoutException) {
                } catch (_: Exception) {
                    if (!running.get()) break
                }
            }
        }, "g20-udp-rx").also {
            it.isDaemon = true
            it.start()
        }
    }

    private fun send(data: ByteArray): Int {
        val sock = socket
        val primary = configuredTarget
        if (sock == null || primary == null) {
            txFail.incrementAndGet()
            lastTxError.set("socket_or_target_null")
            return -1
        }
        try {
            // Prefer connected send; fall back to explicit address.
            if (sock.isConnected) {
                sock.send(DatagramPacket(data, data.size))
            } else {
                sock.send(DatagramPacket(data, data.size, primary))
            }
            txBytes.addAndGet(data.size.toLong())
            txPkts.incrementAndGet()
            lastTxError.set("")
            return data.size
        } catch (e: Exception) {
            // Retry unconnected explicit send once.
            try {
                if (sock.isConnected) {
                    try {
                        sock.disconnect()
                    } catch (_: Exception) {
                    }
                }
                sock.send(DatagramPacket(data, data.size, primary))
                txBytes.addAndGet(data.size.toLong())
                txPkts.incrementAndGet()
                lastTxError.set("recovered_after_disconnect")
                return data.size
            } catch (e2: Exception) {
                txFail.incrementAndGet()
                lastTxError.set(e2.javaClass.simpleName + ":" + (e2.message ?: ""))
                return -1
            }
        }
    }

    private fun stats(): Map<String, Any> {
        val peer = learnedPeer.get()
        return mapOf(
            "bindMode" to bindMode,
            "rxBytes" to rxBytes.get(),
            "txBytes" to txBytes.get(),
            "rxPkts" to rxPkts.get(),
            "txPkts" to txPkts.get(),
            "txFail" to txFail.get(),
            "peer" to if (peer != null) "${peer.address.hostAddress}:${peer.port}" else "",
            "configured" to (configuredTarget?.let { "${it.address.hostAddress}:${it.port}" } ?: ""),
            "lastTxError" to lastTxError.get(),
            "targetListen" to targetListenState.get(),
        )
    }

    fun close() {
        closeLocked()
    }

    private fun closeLocked() {
        running.set(false)
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
        rxThread = null
        configuredTarget = null
        learnedPeer.set(null)
    }

    private fun readBytes(raw: Any?): ByteArray? {
        return when (raw) {
            is ByteArray -> raw
            is List<*> -> {
                val out = ByteArray(raw.size)
                for (i in raw.indices) {
                    val v = raw[i]
                    out[i] = when (v) {
                        is Int -> v.toByte()
                        is Long -> v.toByte()
                        else -> return null
                    }
                }
                out
            }
            else -> null
        }
    }
}
