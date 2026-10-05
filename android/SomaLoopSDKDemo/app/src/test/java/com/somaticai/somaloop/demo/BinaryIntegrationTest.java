package com.somaticai.somaloop.demo;
import org.junit.Test;
import static org.junit.Assert.*;
import com.somaticai.somaloop.*;
import java.util.Collections;
import kotlinx.serialization.json.JsonObject;
import kotlinx.serialization.json.JsonPrimitive;

public final class BinaryIntegrationTest {
    @Test public void binaryACCAndBatteryContactAPIs() throws Exception {
        assertEquals("accOnly", ApiViews.serverMode(CaptureMode.accOnly));
        byte[] bytes = new byte[44]; bytes[0] = 0x33; bytes[1] = (byte) 0xff; bytes[2] = (byte) 0xff; bytes[43] = (byte) 0xff;
        ACCFrame frame = ACCFrame.parse(bytes);
        assertNotNull(frame); assertEquals(6, frame.getSamples().size());
        assertEquals(-1, frame.getSamples().get(0).getX()); assertEquals(255, frame.getSequence());
        BatteryReading battery = new BatteryReading(new ReportedValue(75, 75.0, "percent", "raw"), "134b02341200000000000000000000a6");
        assertEquals(Integer.valueOf(2), battery.getChargingStateRaw()); assertEquals(ChargingState.unknown, battery.getChargingState());
        assertEquals(4660, battery.getVoltage().getRawValue()); assertNull(battery.getVoltage().getUnit());
        assertNotNull(WearStatus.unknown);
        assertNotNull(SomaLoopJava.class.getMethod("readWearState", double.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("readBattery", SomaLoopJava.Callback.class));
    }
    @Test public void firmware0088Capabilities() {
        DeviceProfile p = DeviceProfile.Companion.identify("test", "66778899aabb", "00000808", "260604", "New device");
        assertEquals(CapabilityState.compatibleCandidate, p.getState());
        assertEquals(CapabilityState.compatibleCandidate, p.capability("ppgOnly"));
        assertEquals(CapabilityState.compatibleCandidate, p.capability("measurements"));
        assertEquals(CapabilityState.compatibleCandidate, p.capability("hapticRhythm"));
        assertEquals(CapabilityState.compatibleCandidate, p.capability("rawECG"));
        assertEquals(CapabilityState.untested, p.capability("diagnostics"));
        assertEquals(CapabilityState.compatibleCandidate, p.historyCapability(HistoryKind.sleep));
        for (HistoryKind kind : HistoryKind.values()) {
            assertFalse(kind.getExperimental());
            assertEquals(CapabilityState.compatibleCandidate, p.historyCapability(kind));
        }
        assertEquals(CapabilityState.compatibleCandidate, p.settingsCapability(SettingKind.alarms, 1));
    }
    @Test public void activeMeasurementButtonUsesItsCapabilityAndPreservesRuntimeChecks() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        CapabilityEntry entry = new CapabilityEntry(CapabilityState.compatibleCandidate, true, false,
                "Active measurement may be requested; results depend on device notifications");
        CapabilitySnapshot snapshot = new CapabilitySnapshot(1, "synthetic", "0.0.9.9", null, false,
                Collections.singletonMap("measurements", entry), Collections.emptyMap());
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), snapshot));
        assertTrue(ui.availability("measurements", false).getEnabled());
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        Long operation = ui.beginOperation();
        assertFalse(ui.availability("measurements", false).getEnabled());
        ui.endOperation(operation);
        assertTrue(ui.availability("measurements", false).getEnabled());
        ui.updateHaptics(binding, true);
        assertFalse(ui.availability("measurements", false).getEnabled());
        ui.updateHaptics(binding, false);
        ui.updateSession(binding, true, false);
        assertFalse(ui.availability("measurements", false).getEnabled());
        ui.updateSession(binding, false, false);
        ui.connectionChanged(binding, ConnectionState.disconnected);
        assertFalse(ui.availability("measurements", false).getEnabled());
    }
    @Test public void firmwareRangeAndEvidenceAreIndependent() {
        for (String firmware : new String[] {"00000808", "00000809", "00000999", "00010000", "99999999"}) {
            DeviceProfile p = DeviceProfile.Companion.identify("test", "000000000001", firmware, "260605", null);
            assertTrue(p.getPermitsKnownProtocol());
            assertEquals(CapabilityState.compatibleCandidate, p.getState());
            assertEquals(CapabilityState.compatibleCandidate, p.capability("ppgOnly"));
            assertEquals(CapabilityState.compatibleCandidate, p.capability("rawECG"));
            assertEquals(CapabilityState.untested, p.capability("diagnostics"));
            assertEquals(CapabilityState.untested, p.capability("ppgAccPaired"));
            assertEquals(CapabilityState.compatibleCandidate, p.capability("measurements"));
            assertEquals(CapabilityState.compatibleCandidate, p.historyCapability(HistoryKind.sleep));
        }
        for (String firmware : new String[] {"00000000", "00000709", "00000807", "0000070a", "000007ff", "0000080g", "00000808 "}) {
            DeviceProfile forged = new DeviceProfile("somaloop-fw-00000709-260519", "test", "001122334455", firmware, "260519", CapabilityState.verifiedReference, null);
            assertFalse(forged.getPermitsKnownProtocol());
            assertEquals(CapabilityState.untested, forged.capability("ppgOnly"));
            assertEquals(CapabilityState.untested, forged.capability("rawECG"));
            assertEquals(CapabilityState.untested, forged.capability("measurements"));
        }
        DeviceProfile existing = DeviceProfile.Companion.identify("test", "000000000001", "00000808", "260604", null);
        assertEquals(CapabilityState.compatibleCandidate, existing.capability("measurements"));
        assertEquals(CapabilityState.compatibleCandidate, existing.capability("hapticRhythm"));
        assertEquals(CapabilityState.compatibleCandidate, existing.capability("rawECG"));
        assertEquals(CapabilityState.untested, existing.capability("diagnostics"));
    }
    @Test public void hapticBinaryContract() throws Exception {
        assertNotNull(SomaLoopJava.class.getMethod("playHaptics", HapticPattern.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("playHaptics", HapticPattern.class, boolean.class, SomaLoopJava.Callback.class));
        HapticPlan plan = HapticPattern.firstPulse.compile();
        assertEquals(2000.0, plan.getDurationMs(), 0.001);
        assertEquals(6, plan.getEvents().size());
        assertEquals(HapticStep.SHORT, plan.getPattern().getSteps().get(0));
    }
    @Test public void typedReadOptInPreservesExistingJvmEntryPoints() throws Exception {
        Class<?> continuation = kotlin.coroutines.Continuation.class;
        assertNotNull(SomaLoopClient.class.getMethod("readHistoryBatch", HistoryKind.class, boolean.class, int.class, boolean.class, Integer.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("readHistoryBatch", HistoryKind.class, boolean.class, int.class, boolean.class, boolean.class, Integer.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("syncHistory", HistoryKind.class));
        assertNotNull(SomaLoopClient.class.getMethod("syncHistory", HistoryKind.class, boolean.class));
        assertNotNull(SomaLoopClient.class.getMethod("syncHistory", HistoryKind.class, boolean.class, boolean.class));
        assertNotNull(SomaLoopClient.class.getMethod("syncHistoryRecords", HistoryKind.class, HistorySyncOptions.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("syncHistoryRecords", HistoryKind.class, HistorySyncOptions.class, boolean.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("readSettings", SettingKind.class, int.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("readSettings", SettingKind.class, int.class, boolean.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("readSettings", SettingKind.class, int.class, boolean.class, boolean.class, continuation));
        assertNotNull(SomaLoopJava.class.getMethod("readHistoryBatch", HistoryKind.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("readHistoryBatch", HistoryKind.class, boolean.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("readHistoryBatch", HistoryKind.class, boolean.class, boolean.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("readSettings", SettingKind.class, int.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("readSettings", SettingKind.class, int.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("readSettings", SettingKind.class, int.class, boolean.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("syncHistoryRecords", HistoryKind.class, HistorySyncOptions.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("syncHistoryRecords", HistoryKind.class, HistorySyncOptions.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(HistorySyncOptions.class.getConstructor(DeviceCalendar.class, HistoryCheckpoint.class, String.class, boolean.class, int.class, int.class, boolean.class, Integer.class));
    }
    @Test public void erasureBinaryContractRequiresPreparationConfirmationAndExperimentalOptIn() throws Exception {
        Class<?> continuation = kotlin.coroutines.Continuation.class;
        assertNotNull(SomaLoopClient.class.getMethod("prepareHistoryErasure", java.util.List.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("prepareHistoryErasure", java.util.List.class, boolean.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("eraseHistory", HistoryErasurePreparation.class, boolean.class, continuation));
        assertNotNull(SomaLoopClient.class.getMethod("eraseHistory", HistoryErasurePreparation.class, boolean.class, boolean.class, continuation));
        assertNotNull(SomaLoopJava.class.getMethod("prepareHistoryErasure", java.util.List.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("prepareHistoryErasure", java.util.List.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("eraseHistory", HistoryErasurePreparation.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("eraseHistory", HistoryErasurePreparation.class, boolean.class, boolean.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("lastHistoryErasureReport", SomaLoopJava.Callback.class));
        for (String firmware : new String[] {"00000808"}) {
            DeviceProfile profile = DeviceProfile.Companion.identify("test", "001122334455", firmware, "260604", null);
            assertEquals(CapabilityState.experimental, profile.capability("historyErasure"));
        }
        HistoryErasurePreparation preparation = new HistoryErasurePreparation("token", "identity", Collections.singletonList(HistoryKind.temperature), 100.0, 130.0);
        assertEquals(30.0, preparation.getExpiresAt() - preparation.getCreatedAt(), 0.001);
        HistoryErasureKindResult result = new HistoryErasureKindResult(HistoryKind.temperature, true, true, HistoryErasureVerification.empty, 0, true, null);
        HistoryErasureReport report = new HistoryErasureReport("token", "identity", 100.0, 101.0, Collections.singletonList(result), true, true, null);
        assertTrue(report.getReadbackEmpty());
        assertFalse(new HistoryErasureReport("token", "identity", 100.0, 101.0, Collections.singletonList(result), true, false, null).getReadbackEmpty());
    }
    @Test public void motorControlIsNormallyAvailableAcrossDeviceAddresses() {
        for (String mac : new String[] {"001122334455", "66778899aabb"}) {
            DeviceProfile p = DeviceProfile.Companion.identify("test", mac, "00000808", "260604", null);
            assertEquals(CapabilityState.compatibleCandidate, p.capability("hapticRhythm"));
            DemoCapabilityState ui = new DemoCapabilityState();
            long binding = ui.bind(ConnectionState.ready);
            idleRuntime(ui, binding);
            CapabilityEntry entry = new CapabilityEntry(p.capability("hapticRhythm"), true, false,
                    "Motor vibration and host-scheduled rhythm available");
            CapabilitySnapshot snapshot = new CapabilitySnapshot(1, p.getMac(), "0.0.8.8", "2026-06-04", true,
                    Collections.singletonMap("hapticRhythm", entry), Collections.emptyMap());
            assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), snapshot));
            assertTrue(ui.availability("hapticRhythm", false).getEnabled());
            assertFalse(ui.availability("hapticRhythm", false).getReason().contains("实验"));
            assertTrue(ui.updateHaptics(binding, true));
            assertFalse(ui.availability("hapticRhythm", false).getEnabled());
            assertTrue(ui.recoveryAvailability().getEnabled());
        }
    }
    @Test public void binaryProfileIdentity() {
        DeviceProfile p = DeviceProfile.Companion.identify("test", "001122334455", "00000808", "260604", "Original BLE name");
        assertEquals("somaloop-fw-00000808-260604", p.getId());
        assertEquals("Original BLE name", p.getAdvertisedName());
        assertEquals(CapabilityState.compatibleCandidate, p.getState());
    }
    @Test public void binaryPublicContractLoads() throws Exception {
        assertEquals("SomaLoop 2 SDK", SomaLoop.product);
        assertTrue(SomaLoop.version.startsWith("0.1."));
        assertEquals(64, SomaLoop.buildRevision.length());
        String expectedRevision = System.getenv("SOMALOOP_EXPECTED_REVISION");
        if (expectedRevision != null) assertEquals(expectedRevision, SomaLoop.buildRevision);
        assertEquals("0.0.8.8", FirmwareVersion.parse("00000808").getDotted());
        assertNotNull(new HistorySyncOptions());
        assertNull(ECGFrame.parse(new byte[180]));
        assertNotNull(SomaLoopJava.class.getMethod("recordECG", int.class, SomaLoopJava.Callback.class));
        assertNotNull(SomaLoopJava.class.getMethod("stopResearch", SomaLoopJava.Callback.class));
    }
    @Test public void explicitPowerDebugContractRetainsOriginalPartialCalendar() {
        byte[] bytes = new byte[HistoryKind.powerDebug.getRecordLength()];
        bytes[0] = 0x67; bytes[1] = 1;
        bytes[3] = 0x10; bytes[4] = 0x01; bytes[5] = 0x14; bytes[6] = 0x59; bytes[7] = 7;
        HistoryRecord record = HistoryDecoder.replay(HistoryKind.powerDebug, Collections.singletonList(bytes)).get(0);
        String deviceID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
        SomaAdaptationResult result = SomaContractAdapter.historyForContract(record, deviceID, SomaContractRevision.partialCalendarHistoryV1);
        assertTrue(result.getRejections().isEmpty());
        assertEquals(1, result.getObjects().size());
        JsonObject object = result.getObjects().get(0);
        assertEquals(6, object.size());
        assertEquals("soma.history-record/v1", ((JsonPrimitive)object.get("schema")).getContent());
        assertEquals("powerDebug", ((JsonPrimitive)object.get("kind")).getContent());
        assertEquals("10011459", ((JsonPrimitive)object.get("device_date")).getContent());
        assertEquals("minute_no_year", ((JsonPrimitive)object.get("precision")).getContent());
        assertEquals(record.getRawHex(), ((JsonPrimitive)object.get("raw_hex")).getContent());
        assertEquals(deviceID, ((JsonPrimitive)object.get("device_id")).getContent());
        assertEquals(Collections.singletonList(record), result.getRetainedRawRecords());
        assertNull(record.getDeviceCalendar());
        assertEquals("null", result.getProvenance().get(0).get("record_id").toString());
        assertEquals(SomaContractRevision.partialCalendarHistoryV1.getRevision(), ((JsonPrimitive)result.getProvenance().get(0).get("server_contract_revision")).getContent());
        assertEquals(SomaContractRevision.legacyV1, SomaContractAdapter.defaultContractRevision);
        assertTrue(SomaContractAdapter.history(record, deviceID).getObjects().isEmpty());
        SomaAdaptationResult previous = SomaContractAdapter.historyForContract(record, deviceID, SomaContractRevision.diagnosticHistoryV1);
        assertTrue(previous.getObjects().isEmpty());
        assertEquals("calendarPrecisionInsufficient", previous.getRejections().get(0).getReason());
    }
    @Test public void ecgReceiptTimingAndLegacyJavaEntriesRemainAccessible() throws Exception {
        ECGReceptionTiming timing = new ECGReceptionTiming(10.0, 2, 1.0, 9.0, 8.0, 1.0, 1.0);
        java.util.List<ECGFrame> frames = java.util.Arrays.asList(
                new ECGFrame(42, java.util.Arrays.asList(7L, 8L), "", "synthetic-first"),
                new ECGFrame(43, Collections.singletonList(9L), "", "synthetic-second"));
        String meaning = "Host operation boundaries only; no per-sample timestamps";
        ECGRecording recording = new ECGRecording(60, 100.0, 110.0, frames, true, null, "unsigned24Raw", null, meaning, timing);
        assertEquals(10.0, recording.getReceptionTiming().getObservationDurationSeconds(), 0.0);
        assertEquals(2, timing.getReceivedFrameCount());
        assertEquals(Double.valueOf(1.0), timing.getFirstFrameOffsetSeconds());
        assertEquals(Double.valueOf(9.0), timing.getLastFrameOffsetSeconds());
        assertEquals(Double.valueOf(8.0), timing.getMaximumInterFrameGapSeconds());
        assertEquals(1.0, timing.getLeadingSilenceSeconds(), 0.0);
        assertEquals(1.0, timing.getTrailingSilenceSeconds(), 0.0);
        ECGReceptionSummary summary = ApiViews.ecgReceptionSummary(recording);
        assertSame(timing, summary.getReceptionTiming());
        assertEquals(2, summary.getFrameCount());
        assertEquals(3, summary.getSampleCount());
        assertEquals("unknown", summary.getCompleteness());
        assertNull(summary.getSampleRateHz());
        assertNull(summary.getExpectedSampleCount());
        assertNotNull(ECGReceptionSummary.class.getConstructor(int.class, int.class, int.class));
        assertNotNull(ECGReceptionSummary.class.getMethod("copy", int.class, int.class, int.class));
        ECGReceptionSummary legacySummary = new ECGReceptionSummary(2, 3, 0);
        assertEquals("unknown", legacySummary.getCompleteness());
        assertNull(legacySummary.getReceptionTiming());
        ECGReceptionSummary summaryCopy = summary.copy(4, 8, 1);
        assertEquals(4, summaryCopy.getFrameCount());
        assertEquals(8, summaryCopy.getSampleCount());
        assertEquals(1, summaryCopy.getSequenceDiscontinuityCount());
        assertEquals("unknown", summaryCopy.getCompleteness());
        assertSame(timing, summaryCopy.getReceptionTiming());
        assertNull(legacySummary.copy(4, 8, 1).getReceptionTiming());
        ECGReceptionSummary oldSummaryJSON = ModelsKt.getSdkJson().decodeFromString(ECGReceptionSummary.Companion.serializer(), "{\"frameCount\":2,\"sampleCount\":3,\"sequenceDiscontinuityCount\":0}");
        assertEquals(legacySummary, oldSummaryJSON);
        String encoded = ModelsKt.getSdkJson().encodeToString(ECGRecording.Companion.serializer(), recording);
        assertEquals(recording, ModelsKt.getSdkJson().decodeFromString(ECGRecording.Companion.serializer(), encoded));
        String legacyJSON = "{\"requestedSeconds\":60,\"startedAt\":100.0,\"endedAt\":110.0,\"frames\":[],\"stopConfirmed\":true,\"interruption\":null}";
        ECGRecording decoded = ModelsKt.getSdkJson().decodeFromString(ECGRecording.Companion.serializer(), legacyJSON);
        assertNull(decoded.getReceptionTiming());
        assertNull(ApiViews.ecgReceptionSummary(decoded).getReceptionTiming());
        Class<?>[] legacyTypes = {int.class, double.class, double.class, java.util.List.class, boolean.class, ErrorCode.class, String.class, Double.class, String.class};
        assertNotNull(ECGRecording.class.getConstructor(legacyTypes));
        assertNotNull(ECGRecording.class.getMethod("copy", legacyTypes));
        ECGRecording legacy = new ECGRecording(60, 100.0, 110.0, frames, true, null, "unsigned24Raw", null, meaning);
        assertNull(legacy.getReceptionTiming());
        ECGRecording copied = recording.copy(61, 100.0, 110.0, frames, true, null, "unsigned24Raw", null, meaning);
        assertEquals(61, copied.getRequestedSeconds());
        assertSame(timing, copied.getReceptionTiming());
        assertEquals(frames, copied.getFrames());
        assertNull(legacy.copy(61, 100.0, 110.0, frames, true, null, "unsigned24Raw", null, meaning).getReceptionTiming());
    }
    @Test public void pairedParserJavaConstructorsAndManifestMetadata() {
        PairedDebugParser legacy = new PairedDebugParser();
        assertEquals(1, legacy.getMetadata().getRevision());
        assertNull(legacy.getMetadata().getPairedProfileID());
        DeviceProfile device = DeviceProfile.Companion.identify("test", "000000000001", "00000808", "260604", null);
        PairedDebugParser scoped = new PairedDebugParser(device);
        assertEquals("paired-fw-00000808-260604", scoped.getMetadata().getPairedProfileID());
        assertEquals(Integer.valueOf(1), scoped.getMetadata().getPairedProfileRevision());
        assertEquals(scoped.getMetadata(), scoped.snapshot().getMetadata());
        String encoded = "{\"parserRevision\":2,\"device\":{\"id\":\"forged\",\"deviceID\":\"test\",\"mac\":\"000000000001\",\"firmwareHex\":\"00000808\",\"dateHex\":\"260604\",\"state\":\"untested\"},\"mode\":\"ppg_acc_paired\",\"plannedEndAt\":0,\"pairedProfileID\":\"paired-fw-00000808-260604\",\"pairedProfileRevision\":1}";
        SessionManifest manifest = ModelsKt.getSdkJson().decodeFromString(SessionManifest.Companion.serializer(), encoded);
        assertEquals(2, manifest.getParserRevision());
        assertEquals(manifest.getPairedProfileID(), new PairedDebugParser(manifest).getMetadata().getPairedProfileID());
        SessionManifest missing = ModelsKt.getSdkJson().decodeFromString(SessionManifest.Companion.serializer(), encoded.replace(",\"pairedProfileRevision\":1", ""));
        assertThrows(SDKException.class, () -> new PairedDebugParser(missing));
    }
    @Test public void publicSleepTimingUsesScopedProtocolRule() {
        byte[] bytes = new byte[130];
        bytes[0] = 0x53; bytes[3] = 0x26; bytes[4] = 0x09; bytes[5] = 0x28;
        bytes[6] = 0x12; bytes[9] = 2; bytes[10] = 1; bytes[11] = 0;
        HistoryRecord record = HistoryDecoder.replay(HistoryKind.sleep, Collections.singletonList(bytes)).get(0);
        DeviceProfile profile = DeviceProfile.Companion.identify("test", "000000000001", "00000808", "260604", null);
        SleepTimelineResult result = SleepTimelineResolver.resolve(record, profile, 480);
        assertEquals(SleepTimelineStatus.resolved, result.getStatus());
        assertNull(result.getReason());
        assertEquals(2, result.getRawSlots().size());
        assertEquals(0L, result.getRawSlots().get(1).getRawValue());
        assertEquals(2, result.getIntervals().size());
        assertEquals(60_000L, result.getIntervals().get(0).getEndUnixMilliseconds() - result.getIntervals().get(0).getStartUnixMilliseconds());
        SleepRecordStart start = SleepTimelineResolver.recordStart(record, profile, 480);
        assertNotNull(start);
        assertEquals(record.getDeviceCalendar(), start.getDeviceCalendar());
        assertEquals(Long.valueOf((long)(record.getDeviceCalendar().epochSeconds(480) * 1000)), start.getUnixMilliseconds());
        assertEquals("userConfirmed", start.getEvidenceSource());
        assertFalse(start.getIndependentlyValidated());
        assertNull(SleepTimelineResolver.recordStart(record, profile).getUnixMilliseconds());
        SomaAdaptationResult adaptation = SomaContractAdapter.history(record, "01ARZ3NDEKTSV4RRFFQ69G5FAV",
                new HistoryTimeContract("firstSample", 60.0, 480, "caller-provided claim"), null, profile);
        assertEquals(3, adaptation.getObjects().size());
        assertTrue(adaptation.getRejections().isEmpty());
        SleepTimingRuleInfo info = SleepTimelineResolver.ruleInfo(profile);
        assertNotNull(info);
        assertEquals("protocolReferenceAndUserConfirmation", info.getEvidenceSource());
        assertFalse(info.getIndependentlyValidated());
        assertEquals("protocolReference", info.getStageMappingSource());
        assertFalse(info.getStageAccuracyIndependentlyValidated());
        assertEquals(60, info.getCodeDurationSeconds());
        SomaAdaptationResult automatic = SomaContractAdapter.historyWithDeviceTiming(record, "01ARZ3NDEKTSV4RRFFQ69G5FAV", profile, 480);
        assertEquals(adaptation.getObjects(), automatic.getObjects());
        assertEquals(automatic.getObjects(), SomaContractAdapter.historyWithDeviceTiming(Collections.singletonList(record), "01ARZ3NDEKTSV4RRFFQ69G5FAV", profile, 480).getObjects());
        byte[] heartBytes = new byte[24];
        heartBytes[0] = 0x54;
        System.arraycopy(bytes, 3, heartBytes, 3, 6);
        java.util.Arrays.fill(heartBytes, 9, 24, (byte)72);
        HistoryRecord heartRecord = HistoryDecoder.replay(HistoryKind.heartRate, Collections.singletonList(heartBytes)).get(0);
        assertEquals(1, SomaContractAdapter.history(heartRecord, "01ARZ3NDEKTSV4RRFFQ69G5FAV").getObjects().size());
        SomaAdaptationResult heartAdaptation = SomaContractAdapter.historyWithDeviceTiming(heartRecord, "01ARZ3NDEKTSV4RRFFQ69G5FAV", profile, 480);
        assertEquals(2, heartAdaptation.getObjects().size());
        assertNotNull(heartAdaptation.getProvenance().get(0).get("device_time_rule"));
    }

    @Test public void demoAlreadyReadyBindingLoadsWithoutDeviceEvent() {
        DemoCapabilityState ui = new DemoCapabilityState();
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        assertEquals("正在读取能力快照", ui.availability("ppgOnly", false).getReason());
        DemoSnapshotRequest request = ui.requestSnapshot(binding);
        assertNotNull(request);
        assertTrue(ui.applySnapshot(request, demoSnapshot(true, availableEntry())));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
        assertEquals("已验证采集能力", ui.availability("ppgOnly", false).getReason());
        assertTrue(ui.availability(null, false).getEnabled());
        // The replayed current state must not erase the snapshot already obtained at binding.
        assertTrue(ui.connectionChanged(binding, ConnectionState.ready));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
    }

    @Test public void demoDisconnectNeedsFreshSnapshotBeforeEnablingAgain() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, availableEntry())));
        DemoSnapshotRequest delayed = ui.requestSnapshot(binding);
        assertTrue(ui.connectionChanged(binding, ConnectionState.disconnected));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertEquals("手环未就绪（disconnected）", ui.availability("ppgOnly", false).getReason());
        assertNull(ui.requestSnapshot(binding));
        assertFalse(ui.applySnapshot(delayed, demoSnapshot(true, availableEntry())));
        assertTrue(ui.connectionChanged(binding, ConnectionState.ready));
        assertFalse(ui.applySnapshot(delayed, demoSnapshot(true, availableEntry())));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, availableEntry())));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
    }

    @Test public void demoServiceRebindRejectsPreviousObserversAndSnapshot() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long oldBinding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, oldBinding);
        DemoSnapshotRequest delayed = ui.requestSnapshot(oldBinding);
        ui.detach();
        assertFalse(ui.recoveryAvailability().getEnabled());
        assertEquals("采集服务尚未连接", ui.availability("ppgOnly", false).getReason());
        long newBinding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, newBinding);
        assertNotEquals(oldBinding, newBinding);
        assertFalse(ui.isCurrent(oldBinding));
        assertFalse(ui.connectionChanged(oldBinding, ConnectionState.disconnected));
        assertNull(ui.requestSnapshot(oldBinding));
        assertFalse(ui.applySnapshot(delayed, demoSnapshot(true, availableEntry())));
        assertTrue(ui.applySnapshot(ui.requestSnapshot(newBinding), demoSnapshot(true, availableEntry())));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.recoveryAvailability().getEnabled());
    }

    @Test public void demoLatestSnapshotWinsWithinBinding() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        DemoSnapshotRequest older = ui.requestSnapshot(binding);
        DemoSnapshotRequest newer = ui.requestSnapshot(binding);
        CapabilityEntry denied = new CapabilityEntry(CapabilityState.untested, false, false, "此固件尚无验证证据");
        assertTrue(ui.applySnapshot(newer, demoSnapshot(true, denied)));
        assertFalse(ui.applySnapshot(older, demoSnapshot(true, availableEntry())));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertEquals("此固件尚无验证证据", ui.availability("ppgOnly", false).getReason());
    }

    @Test public void demoExperimentalOptInCannotBypassProtocolAdmission() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        CapabilityEntry experiment = new CapabilityEntry(CapabilityState.experimental, false, true, "需显式试用");
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, experiment)));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.availability("ppgOnly", true).getEnabled());
        assertTrue(ui.availability("ppgOnly", true).getReason().contains("实验功能"));
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(false, experiment)));
        assertFalse(ui.availability("ppgOnly", true).getEnabled());
        assertFalse(ui.availability(null, false).getEnabled());
        assertEquals("当前固件未通过协议准入", ui.availability("ppgOnly", true).getReason());
    }

    @Test public void demoHistoryShowsItsOwnUnavailableReason() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        CapabilityEntry history = new CapabilityEntry(CapabilityState.untested, false, false, "温度历史待验证");
        CapabilitySnapshot snapshot = new CapabilitySnapshot(1, "demo-device", "0.0.8.8", "2026-06-04", true,
                Collections.singletonMap("ppgOnly", availableEntry()), Collections.singletonMap("98", history));
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), snapshot));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
        assertFalse(ui.availability("history:98", false).getEnabled());
        assertEquals("温度历史待验证", ui.availability("history:98", false).getReason());
        assertFalse(ui.availability("history:99", false).getEnabled());
        assertEquals("SDK 未报告此能力", ui.availability("history:99", false).getReason());
        assertTrue(ui.connectionChanged(binding, ConnectionState.reconnecting));
        assertEquals("手环未就绪（reconnecting）", ui.availability("history:98", false).getReason());
    }

    @Test public void demoStopRecoveryAndConfirmationRemainAvailableWithoutBle() {
        DemoCapabilityState ui = new DemoCapabilityState();
        assertFalse(ui.recoveryAvailability().getEnabled());
        long binding = ui.bind(ConnectionState.disconnected);
        for (ConnectionState state : ConnectionState.values()) {
            assertTrue(ui.connectionChanged(binding, state));
            assertTrue("Safety actions must remain available in " + state, ui.recoveryAvailability().getEnabled());
            assertFalse(ui.availability("ppgOnly", false).getEnabled());
        }
        ui.detach();
        assertFalse(ui.recoveryAvailability().getEnabled());
    }

    @Test public void demoBusyCountersAndCaptureCleanupGateNormalActions() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, availableEntry())));
        long first = ui.beginOperation();
        long second = ui.beginOperation();
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertEquals("设备操作进行中，请等待完成", ui.availability("ppgOnly", false).getReason());
        assertTrue(ui.recoveryAvailability().getEnabled());
        ui.endOperation(first);
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        ui.endOperation(second);
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.updateSession(binding, true, false));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.updateSession(binding, false, true));
        assertEquals("采集进行中或等待停止清理", ui.availability(null, false).getReason());
        assertTrue(ui.recoveryAvailability().getEnabled());
        assertTrue(ui.updateSession(binding, false, false));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
    }

    @Test public void demoBindingWaitsForRuntimeAndIgnoresOldOperationCompletion() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long oldBinding = ui.bind(ConnectionState.ready);
        assertTrue(ui.applySnapshot(ui.requestSnapshot(oldBinding), demoSnapshot(true, availableEntry())));
        assertEquals("正在读取会话和停止状态", ui.availability("ppgOnly", false).getReason());
        assertTrue(ui.updateSession(oldBinding, false, false));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.updateHaptics(oldBinding, false));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
        long oldOperation = ui.beginOperation();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, availableEntry())));
        long newOperation = ui.beginOperation();
        ui.endOperation(oldOperation);
        assertFalse(ui.updateSession(oldBinding, true, true));
        assertFalse(ui.updateHaptics(oldBinding, true));
        assertEquals("设备操作进行中，请等待完成", ui.availability("ppgOnly", false).getReason());
        ui.endOperation(newOperation);
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
    }

    @Test public void demoHapticPendingPreservesRecoveryAndAdmissionOnlyReads() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        CapabilityEntry untested = new CapabilityEntry(CapabilityState.untested, false, false, "无能力验证证据");
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, untested)));
        // Device info and clock reads require configured protocol admission, not a capability promotion.
        assertTrue(ui.availability(null, false).getEnabled());
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.updateHaptics(binding, true));
        assertFalse(ui.availability(null, false).getEnabled());
        assertEquals("振动尚未确认停止，请先停止并确认", ui.availability(null, false).getReason());
        assertTrue(ui.recoveryAvailability().getEnabled());
        assertTrue(ui.connectionChanged(binding, ConnectionState.disconnected));
        assertTrue(ui.recoveryAvailability().getEnabled());
        assertTrue(ui.updateHaptics(binding, false));
        assertFalse(ui.availability(null, false).getEnabled());
    }

    private static void idleRuntime(DemoCapabilityState ui, long binding) {
        assertTrue(ui.updateSession(binding, false, false));
        assertTrue(ui.updateHaptics(binding, false));
    }

    @Test public void demoRuntimeSnapshotCannotOverwriteNewCaptureOrHapticEvents() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, availableEntry())));
        DemoRuntimeRequest beforeCapture = ui.requestRuntime(binding);
        assertTrue(ui.updateSession(binding, true, true));
        assertFalse(ui.applyRuntime(beforeCapture, false, false, false));
        assertEquals("采集进行中或等待停止清理", ui.availability(null, false).getReason());
        assertTrue(ui.updateSession(binding, false, false));
        DemoRuntimeRequest beforeHaptic = ui.requestRuntime(binding);
        assertTrue(ui.updateHaptics(binding, true));
        assertFalse(ui.applyRuntime(beforeHaptic, false, false, false));
        assertEquals("振动尚未确认停止，请先停止并确认", ui.availability(null, false).getReason());
        DemoRuntimeRequest older = ui.requestRuntime(binding);
        DemoRuntimeRequest latest = ui.requestRuntime(binding);
        assertTrue(ui.applyRuntime(latest, false, false, false));
        assertFalse(ui.applyRuntime(older, true, true, true));
        assertTrue(ui.availability(null, false).getEnabled());
        DemoRuntimeRequest beforeOperation = ui.requestRuntime(binding);
        long operation = ui.beginOperation();
        assertFalse(ui.applyRuntime(beforeOperation, false, false, false));
        ui.endOperation(operation);
        ui.detach();
        assertFalse(ui.applyRuntime(latest, false, false, false));
    }

    @Test public void demoCaptureDispatchInvalidatesCachedIdleState() {
        DemoCapabilityState ui = new DemoCapabilityState();
        long binding = ui.bind(ConnectionState.ready);
        idleRuntime(ui, binding);
        assertTrue(ui.applySnapshot(ui.requestSnapshot(binding), demoSnapshot(true, availableEntry())));
        DemoRuntimeRequest staleIdle = ui.requestRuntime(binding);
        ui.captureStartDispatched(binding);
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.recoveryAvailability().getEnabled());
        assertFalse(ui.applyRuntime(staleIdle, false, false, false));
        assertTrue(ui.applyRuntime(ui.requestRuntime(binding), true, true, false));
        assertFalse(ui.availability("ppgOnly", false).getEnabled());
        assertTrue(ui.applyRuntime(ui.requestRuntime(binding), false, false, false));
        assertTrue(ui.availability("ppgOnly", false).getEnabled());
    }

    private static CapabilityEntry availableEntry() {
        return new CapabilityEntry(CapabilityState.verifiedReference, true, false, "已验证采集能力");
    }

    private static CapabilitySnapshot demoSnapshot(boolean protocolAdmitted, CapabilityEntry entry) {
        return new CapabilitySnapshot(1, "demo-device", "0.0.8.8", "2026-06-04", protocolAdmitted,
                Collections.singletonMap("ppgOnly", entry), Collections.emptyMap());
    }
}
