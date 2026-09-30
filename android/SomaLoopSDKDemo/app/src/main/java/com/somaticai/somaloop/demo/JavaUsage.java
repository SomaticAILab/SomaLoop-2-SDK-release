package com.somaticai.somaloop.demo;
import android.os.Handler;
import android.os.Looper;
import com.somaticai.somaloop.*;

/** Java host integration; use the same service-owned client as the Kotlin demo. */
public final class JavaUsage implements AutoCloseable {
    private final SomaLoopJava sdk;
    public JavaUsage(SomaLoopClient client) {
        Handler main = new Handler(Looper.getMainLooper());
        sdk = new SomaLoopJava(client, command -> main.post(command));
    }
    public void readTemperature(SomaLoopJava.Callback<HistoryBatch> callback) {
        sdk.readHistoryBatch(HistoryKind.temperature, false, callback);
    }
    public void syncTemperature(HistorySyncOptions options, SomaLoopJava.Callback<HistorySyncResult> callback) {
        sdk.syncHistoryRecords(HistoryKind.temperature, options, callback);
    }
    public void readClock(SomaLoopJava.Callback<ClockSnapshot> callback) {
        sdk.readDeviceClock(null, callback);
    }
    public void capabilitySnapshot(SomaLoopJava.Callback<CapabilitySnapshot> callback) {
        sdk.capabilitySnapshot(callback);
    }
    public AutoCloseable observe(SomaLoopJava.Listener listener) { return sdk.observe(listener); }
    @Override public void close() { sdk.close(); }
}
