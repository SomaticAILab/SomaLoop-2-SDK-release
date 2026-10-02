package com.somaticai.somaloop.demo

import android.Manifest
import android.app.Activity
import android.content.*
import android.content.pm.PackageManager
import android.os.*
import android.widget.*
import java.io.File
import java.util.zip.*
import com.somaticai.somaloop.*
import kotlinx.coroutines.*

data class DemoAvailability(val enabled:Boolean,val reason:String)
data class DemoSnapshotRequest(val binding:Long,val revision:Long)
data class DemoRuntimeRequest(val binding:Long,val revision:Long)

/** UI state is rebuilt on every binding; a delayed snapshot cannot revive an old connection. */
class DemoCapabilityState {
    private var binding=0L
    private var revision=0L
    private var runtimeRevision=0L
    private var serviceAvailable=false
    private var connection=ConnectionState.disconnected
    private var snapshot:CapabilitySnapshot?=null
    private var sessionKnown=false
    private var hapticsKnown=false
    private var capturePending=false
    private var hapticPending=false
    private var operations=0

    fun bind(currentConnection:ConnectionState):Long {
        binding++;revision++;serviceAvailable=true;connection=currentConnection;snapshot=null
        sessionKnown=false;hapticsKnown=false;capturePending=false;hapticPending=false;operations=0
        return binding
    }
    fun detach(){binding++;revision++;serviceAvailable=false;connection=ConnectionState.disconnected;snapshot=null}
    fun isCurrent(token:Long)=serviceAvailable&&token==binding
    fun connectionChanged(token:Long,value:ConnectionState):Boolean {
        if(!isCurrent(token))return false
        if(connection!=value){connection=value;revision++;runtimeRevision++;snapshot=null}
        return true
    }
    fun requestSnapshot(token:Long):DemoSnapshotRequest? {
        if(!isCurrent(token)||connection!=ConnectionState.ready)return null
        return DemoSnapshotRequest(binding,++revision)
    }
    fun applySnapshot(request:DemoSnapshotRequest,value:CapabilitySnapshot):Boolean {
        if(!isCurrent(request.binding)||request.revision!=revision||connection!=ConnectionState.ready)return false
        snapshot=value
        return true
    }
    fun updateSession(token:Long,requested:Boolean,cleanupPending:Boolean):Boolean {
        if(!isCurrent(token))return false
        runtimeRevision++;sessionKnown=true;capturePending=requested||cleanupPending
        return true
    }
    fun updateHaptics(token:Long,pendingStop:Boolean):Boolean {
        if(!isCurrent(token))return false
        runtimeRevision++;hapticsKnown=true;hapticPending=pendingStop
        return true
    }
    fun requestRuntime(token:Long):DemoRuntimeRequest? {
        if(!isCurrent(token))return null
        return DemoRuntimeRequest(binding,++runtimeRevision)
    }
    fun applyRuntime(request:DemoRuntimeRequest,requested:Boolean,cleanupPending:Boolean,pendingStop:Boolean):Boolean {
        if(!isCurrent(request.binding)||request.revision!=runtimeRevision)return false
        runtimeRevision++;sessionKnown=true;hapticsKnown=true
        capturePending=requested||cleanupPending;hapticPending=pendingStop
        return true
    }
    fun captureStartDispatched(token:Long){if(isCurrent(token)){runtimeRevision++;sessionKnown=false}}
    fun beginOperation():Long? {if(!serviceAvailable)return null;operations++;runtimeRevision++;return binding}
    fun endOperation(token:Long){if(isCurrent(token))operations=(operations-1).coerceAtLeast(0)}
    fun recoveryAvailability()=DemoAvailability(serviceAvailable,if(serviceAvailable)"可请求停止、恢复或确认停止" else "采集服务尚未连接")
    fun availability(key:String?,experimental:Boolean):DemoAvailability {
        if(!serviceAvailable)return DemoAvailability(false,"采集服务尚未连接")
        if(connection!=ConnectionState.ready)return DemoAvailability(false,"手环未就绪（$connection）")
        val current=snapshot?:return DemoAvailability(false,"正在读取能力快照")
        if(!current.protocolAdmitted&&key!="measurements")return DemoAvailability(false,"当前固件未通过协议准入")
        if(!sessionKnown||!hapticsKnown)return DemoAvailability(false,"正在读取会话和停止状态")
        if(operations>0)return DemoAvailability(false,"设备操作进行中，请等待完成")
        if(capturePending)return DemoAvailability(false,"采集进行中或等待停止清理")
        if(hapticPending)return DemoAvailability(false,"振动尚未确认停止，请先停止并确认")
        if(key==null)return DemoAvailability(true,"手环已就绪")
        val entry=if(key.startsWith("history:"))current.history[key.substringAfter(":")] else current.capabilities[key]
        entry?:return DemoAvailability(false,"SDK 未报告此能力")
        val enabled=entry.available||(experimental&&entry.requiresExperimentalOptIn)
        val reason=if(experimental&&entry.requiresExperimentalOptIn)"实验功能，点击即明确选择试用：${entry.reason}" else entry.reason
        return DemoAvailability(enabled,reason)
    }
}

/** Binary consumer demo: all BLE and capture state belongs to the SDK service. */
class MainActivity:Activity(){
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    private var client:SomaLoopClient?=null;private var bound=false;private var snapshot:File?=null
    private lateinit var status:TextView;private lateinit var stats:TextView;private lateinit var devices:LinearLayout
    private val seen=mutableMapOf<String,Button>()
    private data class CapabilityButton(val button:Button,val reason:TextView,val key:String?,val experimental:Boolean)
    private val capabilityButtons=mutableListOf<CapabilityButton>()
    private val recoveryButtons=mutableListOf<Pair<Button,TextView>>()
    private val capabilityState=DemoCapabilityState()
    private var observationJob:Job?=null
    private var historyCheckpoint:HistoryCheckpoint?=null
    private val service=object:ServiceConnection{
        override fun onServiceConnected(name:ComponentName,binder:IBinder){
            observationJob?.cancel()
            val connected=(binder as SomaLoopCaptureService.LocalBinder).client
            client=connected
            historyCheckpoint=null
            val binding=capabilityState.bind(connected.connectionState.value)
            renderAvailability()
            observe(connected,binding)
        }
        // Android retains the binding registration and may call onServiceConnected again.
        override fun onServiceDisconnected(name:ComponentName){detachService("采集服务已断开，等待重新绑定")}
        override fun onBindingDied(name:ComponentName){detachService("采集服务绑定已失效，请重新打开 Demo");releaseBinding()}
        override fun onNullBinding(name:ComponentName){detachService("采集服务未提供连接，请重新打开 Demo");releaseBinding()}
    }
    override fun onCreate(state:Bundle?){super.onCreate(state)
        val panel=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;setPadding(36,48,36,32)};setContentView(ScrollView(this).apply{addView(panel)})
        fun text(value:String,size:Float=16f)=TextView(this).apply{text=value;textSize=size;setPadding(0,12,0,12);panel.addView(this)}
        fun button(label:String,action:()->Unit):Button=Button(this).apply{text=label;setOnClickListener{action()};panel.addView(this)}
        fun supportedButton(label:String,capability:String?,experimental:Boolean=false,action:()->Unit){val b=button(label,action);val reason=text("采集服务尚未连接",13f);b.isEnabled=false;capabilityButtons+=CapabilityButton(b,reason,capability,experimental)}
        fun recoveryButton(label:String,action:()->Unit){val b=button(label,action);b.isEnabled=false;recoveryButtons+=b to text("采集服务尚未连接",13f)}
        text("Somatic AI SDK Demo",26f);text("Somatic AI · ${SomaLoop.version}");text("本机保存 · Android 24 小时长测待验收",13f)
        status=text("请授权蓝牙后扫描，并按设备标识后缀选择手环");stats=text("尚未开始采集")
        button("授权并扫描手环"){if(permissionsGranted())scan()else requestPermissions(requiredPermissions(),101)}
        devices=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL};panel.addView(devices)
        supportedButton("PPG-only · 24 小时","ppgOnly"){start(CaptureMode.ppgOnly)}
        supportedButton("PPG + ACC · 24 小时","ppgAccPaired"){start(CaptureMode.paired)}
        recoveryButton("停止采集"){runDevice{sdk().stopCapture();status.text="停止意图已保存，请核对停止确认状态"}}
        recoveryButton("恢复待处理会话"){runDevice{if(!sdk().resumePendingSession())status.text="没有待恢复会话"}}
        button("导出会话 ZIP"){run{snapshot=sdk().exportSession(File(cacheDir,"SomaLoopExports"));startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/zip").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,"SomaLoop-${snapshot!!.name}.zip"),102)}}
        text("马达振动 · 默认振动节拍为短、短、长、休止，共 2 秒。",13f)
        button("本地编译预览 · 不触发设备"){run{val p=HapticPattern.firstPulse.compile(true);status.text="预览：${p.durationMs} ms / ${p.events.size / 2} 个脉冲"}}
        supportedButton("振动 2 秒 · 短短长休止","hapticRhythm"){runDevice{val h=sdk().playHaptics(HapticPattern.firstPulse);status.text="振动：${h.status} / ${h.error?:"请确认手环已停止"}"}}
        recoveryButton("立即停止振动"){runDevice{sdk().stopHaptics();status.text="停止已请求；请核对手环是否完全停止"}}
        recoveryButton("确认手环已完全停止"){runDevice{val h=sdk().currentHaptics()?:throw SDKException(ErrorCode.invalidArgument);sdk().confirmHapticsStopped(h.id);status.text="已记录使用者停止确认"}}
        button("导出振动日志 JSON"){run{snapshot=sdk().exportHaptics(File(cacheDir,"SomaLoopExports"));startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,snapshot!!.name),103)}}
        supportedButton("读取设备信息",null){runDevice{val packets=sdk().readDeviceInfo();val capabilities=sdk().capabilitySnapshot();status.text="固件 ${capabilities.firmwareVersion?:"未知"} / ${capabilities.firmwareDate?:"日期未知"}\n电量 ${packets.firstOrNull{it.opcode==0x13}?.fields?.get("batteryPercent")?:"未知"}%"}}
        supportedButton("同步温度历史并对账","history:98"){runDevice{val b=sdk().syncHistoryRecords(HistoryKind.temperature,HistorySyncOptions(checkpoint=historyCheckpoint));historyCheckpoint=b.checkpoint;status.text="新增 ${b.records.size} / 重复 ${b.duplicateRecords} / 页数 ${b.pages} / 完整 ${b.complete} / 中断 ${b.interruption}\n演示检查点仅保存在内存；生产应与入库事务一起保存"}}
        button("查看能力与限制"){run{val snapshot=sdk().capabilitySnapshot();status.text=(snapshot.capabilities+snapshot.history.mapKeys{"history:${it.key}"}).entries.joinToString("\n"){"${it.key}: ${it.value.state} — ${it.value.reason}"}}}
        supportedButton("读取设备时钟（不推断时区）",null){runDevice{val clock=sdk().readDeviceClock();status.text="设备日历 ${clock.deviceCalendar}\n往返 ${clock.roundTripSeconds}s / 偏移需要明确设备UTC偏移"}}
        supportedButton("按手机当前 UTC 偏移校时并回读","clockWrite"){runDevice{val offset=java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis())/60000;val result=sdk().synchronizeClock(offset);historyCheckpoint=null;status.text="校时验证 ${result.verified} / 偏差 ${result.after.offsetSeconds}s / 历史未回填"}}
        button("导出脱敏诊断 JSON"){run{snapshot=sdk().exportDiagnostics(File(cacheDir,"SomaLoopExports"));startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,snapshot!!.name),103)}}
        supportedButton("心率测量 · 40 秒","measurements"){runDevice{status.text="收到 ${sdk().measure(MeasurementKind.heartRate).size} 个实时结果"}}
        text("两路数组独立保存；没有逐点时间戳或一一配对。采集或等待停止时禁用干扰操作；停止与恢复入口保留。设置写入须完成固件验证后开放。",13f)
        bound=bindService(Intent(this,SomaLoopCaptureService::class.java),service,Context.BIND_AUTO_CREATE)
        if(!bound)detachService("无法绑定采集服务，请重新打开 Demo")
    }
    private fun sdk()=client?:throw SDKException(ErrorCode.disconnected,"采集服务尚未就绪")
    private fun showFailure(e:Exception){status.text="${(e as? SDKException)?.code?:"error"}：${e.message}"}
    private fun run(block:suspend()->Unit){scope.launch{try{block()}catch(e:CancellationException){throw e}catch(e:Exception){showFailure(e)}}}
    private fun runDevice(block:suspend()->Unit){
        val connected=client?:return
        val binding=capabilityState.beginOperation()?:return
        renderAvailability()
        run{try{block()}finally{try{refreshRuntime(connected,binding)}finally{capabilityState.endOperation(binding);renderAvailability()}}}
    }
    private fun renderAvailability(){
        capabilityButtons.forEach{item->val value=capabilityState.availability(item.key,item.experimental);item.button.isEnabled=value.enabled;item.reason.text=value.reason;item.button.contentDescription="${item.button.text}：${value.reason}"}
        val recovery=capabilityState.recoveryAvailability()
        recoveryButtons.forEach{(button,reason)->button.isEnabled=recovery.enabled;reason.text=recovery.reason;button.contentDescription="${button.text}：${recovery.reason}"}
    }
    private fun detachService(message:String){observationJob?.cancel();observationJob=null;client=null;capabilityState.detach();historyCheckpoint=null;renderAvailability();status.text=message;stats.text="采集服务不可用，等待重新读取会话状态"}
    private fun releaseBinding(){if(bound){unbindService(service);bound=false}}
    private suspend fun refreshCapabilities(connected:SomaLoopClient,binding:Long){
        val request=capabilityState.requestSnapshot(binding)?:return
        val snapshot=connected.capabilitySnapshot()
        capabilityState.connectionChanged(binding,connected.connectionState.value)
        capabilityState.applySnapshot(request,snapshot)
        if(capabilityState.isCurrent(binding))renderAvailability()
    }
    private suspend fun refreshRuntime(connected:SomaLoopClient,binding:Long){
        val request=capabilityState.requestRuntime(binding)?:return
        val session=connected.currentSession()
        val haptics=connected.currentHaptics()
        if(!capabilityState.applyRuntime(request,session?.requested==true,session?.cleanupPending==true,haptics?.pendingStop==true))return
        stats.text=session?.let{s->"${s.mode} · ${s.status}\nPPG 包 ${s.stats.ppgPackets} / 样本 ${s.stats.ppgSamples}\n联合帧 ${s.stats.pairedFrames} / PPG ${s.stats.pairedPPG} / MEMS ${s.stats.memsTriples}\n停止确认 ${s.stopConfirmed}"}?:"尚未开始采集"
        renderAvailability()
    }
    private suspend fun observeSafely(binding:Long,block:suspend()->Unit){try{block()}catch(e:CancellationException){throw e}catch(e:Exception){if(capabilityState.isCurrent(binding))showFailure(e)}}
    private fun observe(connected:SomaLoopClient,binding:Long){observationJob=scope.launch{
        launch{observeSafely(binding){connected.connectionState.collect{state->
            if(!capabilityState.connectionChanged(binding,state))return@collect
            status.text="连接状态：$state"
            if(state!=ConnectionState.ready)historyCheckpoint=null
            renderAvailability()
            if(state==ConnectionState.ready)refreshCapabilities(connected,binding)
        }}}
        launch{observeSafely(binding){connected.events().collect{event->if(!capabilityState.isCurrent(binding))return@collect;when(event){
        is SDKEvent.Discovery->{val d=event.device;if(d.id !in seen){val button=Button(this@MainActivity).apply{text="设备 ${d.id.filter{it.isLetterOrDigit()}.takeLast(6).uppercase(java.util.Locale.ROOT)} · ${d.rssi} dBm";setOnClickListener{this@MainActivity.run{sdk().stopScan();sdk().connect(d)}}};seen[d.id]=button;devices.addView(button)}}
        is SDKEvent.Device->{historyCheckpoint=null;status.text="固件 ${event.profile.firmwareVersion?.dotted?:"未知"} / ${event.profile.firmwareDate?:"日期未知"} · ${event.profile.state}";refreshCapabilities(connected,binding)}
        is SDKEvent.Health->status.text="采集状态：${event.health.state} / ${event.health.reason}"
        is SDKEvent.Capture->{capabilityState.updateSession(binding,event.session.requested,event.session.cleanupPending);renderAvailability()}
        is SDKEvent.Haptics->{capabilityState.updateHaptics(binding,event.report.pendingStop);renderAvailability();status.text="振动 ${event.report.status} / ${event.report.error?:"无软件错误"} / 待确认停止 ${event.report.pendingStop}"}
        is SDKEvent.Failure->status.text="${event.code}：${event.message}"
        else->Unit
    }}}}
        launch{observeSafely(binding){while(currentCoroutineContext().isActive){refreshRuntime(connected,binding);delay(2000)}}}
    }}
    private fun scan(){seen.clear();devices.removeAllViews();run{sdk().scan()}}
    private fun start(mode:CaptureMode){
        if(!permissionsGranted()){status.text="请先授权蓝牙与通知";return}
        val connected=client?:return
        val binding=capabilityState.beginOperation()?:return
        capabilityState.captureStartDispatched(binding);renderAvailability()
        try{SomaLoopCaptureService.startCapture(this,mode)}catch(e:Exception){showFailure(e);run{refreshRuntime(connected,binding)}}
        finally{capabilityState.endOperation(binding);renderAvailability()}
    }
    private fun requiredPermissions():Array<String> = (if(Build.VERSION.SDK_INT>=31)listOf(Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT)else listOf(Manifest.permission.ACCESS_FINE_LOCATION)).let{if(Build.VERSION.SDK_INT>=33)it+Manifest.permission.POST_NOTIFICATIONS else it}.toTypedArray()
    private fun permissionsGranted()=requiredPermissions().all{checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED}
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grants:IntArray){super.onRequestPermissionsResult(requestCode,permissions,grants);if(requestCode==101&&permissionsGranted())scan()else status.text="权限未授权，请在系统设置中检查"}
    @Deprecated("Platform callback") override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?){super.onActivityResult(requestCode,resultCode,data);if(requestCode==103&&resultCode==RESULT_OK){val uri=data?.data?:return;val file=snapshot?:return;run{withContext(Dispatchers.IO){val out=contentResolver.openOutputStream(uri)?:throw SDKException(ErrorCode.storageFailure);out.use{output->file.inputStream().use{it.copyTo(output)}}};status.text="JSON 已保存"};return};if(requestCode==102&&resultCode==RESULT_OK){val uri=data?.data?:return;val folder=snapshot?:return;run{withContext(Dispatchers.IO){val output=contentResolver.openOutputStream(uri)?:throw SDKException(ErrorCode.storageFailure);ZipOutputStream(output.buffered()).use{zip->folder.listFiles()!!.sortedBy{it.name}.forEach{file->zip.putNextEntry(ZipEntry(file.name));file.inputStream().use{it.copyTo(zip,65536)};zip.closeEntry()}}};status.text="ZIP 已保存；checksums.json 校验内部文件"}}}
    override fun onStart(){super.onStart();run{client?.setHostBackground(false)}}
    override fun onStop(){run{client?.setHostBackground(true)};super.onStop()}
    override fun onDestroy(){releaseBinding();scope.cancel();super.onDestroy()}
}
