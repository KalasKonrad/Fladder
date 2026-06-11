import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/video_player_provider.dart';

class VideoPlayerStatsOverlay extends ConsumerStatefulWidget {
  const VideoPlayerStatsOverlay({super.key});

  @override
  ConsumerState<VideoPlayerStatsOverlay> createState() => _VideoPlayerStatsOverlayState();
}

class _VideoPlayerStatsOverlayState extends ConsumerState<VideoPlayerStatsOverlay> {
  Timer? _refreshTimer;
  _Stats _stats = const _Stats();

  // CPU tracking — needs two readings to compute delta
  int? _prevCpuIdle;
  int? _prevCpuTotal;

  @override
  void initState() {
    super.initState();
    _startRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefresh() {
    _fetchStats();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchStats());
  }

  Future<void> _fetchStats() async {
    final player = ref.read(videoPlayerProvider);
    Future<String?> p(String key) => player.getProperty(key);

    // Run mpv queries and system queries concurrently
    final mpvFuture = Future.wait([
      p('video-codec'),
      p('hwdec-current'),
      p('video-params/w'),
      p('video-params/h'),
      p('estimated-vf-fps'),
      p('container-fps'),
      p('video-params/pixelformat'),
      p('video-params/gamma'),
      p('video-params/primaries'),
      p('audio-codec'),
      p('audio-params/hr-channels'),
      p('audio-params/samplerate'),
      p('audio-bitrate'),
      p('current-vo'),
      p('display-fps'),
      p('estimated-display-fps'),
      p('video-out-params/w'),
      p('video-out-params/h'),
      p('video-out-params/pixelformat'),
      p('media-title'),
      p('filename'),
      p('file-format'),
      p('file-size'),
      p('duration'),
      p('video-bitrate'),
      p('avsync'),
      p('frame-drop-count'),
      p('decoder-frame-drop-count'),
      p('vo-drop-frame-count'),
      p('mistimed-frame-count'),
      p('vsync-ratio'),
      p('demuxer-cache-duration'),
      p('cache-speed'),
      p('deinterlace'),
      p('tone-mapping'),
      p('video-sync'),
      p('interpolation'),
      p('tscale'),
      p('target-colorspace-hint'),
    ]);

    final cpuFuture = _readCpuUsage();
    final gpuFuture = _readGpuStats();

    final results = await mpvFuture;
    final cpuUsage = await cpuFuture;
    final gpuStats = await gpuFuture;

    if (!mounted) return;
    setState(() {
      _stats = _Stats(
        videoCodec: results[0],
        hwdec: results[1],
        width: results[2],
        height: results[3],
        vfFps: results[4],
        containerFps: results[5],
        pixelFormat: results[6],
        gamma: results[7],
        primaries: results[8],
        audioCodec: results[9],
        audioChannels: results[10],
        sampleRate: results[11],
        audioBitrate: results[12],
        currentVo: results[13],
        displayFps: results[14],
        estimatedDisplayFps: results[15],
        outWidth: results[16],
        outHeight: results[17],
        outPixelFormat: results[18],
        mediaTitle: results[19],
        filename: results[20],
        fileFormat: results[21],
        fileSize: results[22],
        duration: results[23],
        videoBitrate: results[24],
        avSync: results[25],
        dropCount: results[26],
        decoderDropCount: results[27],
        voDropCount: results[28],
        mistimedCount: results[29],
        vsyncRatio: results[30],
        cacheDuration: results[31],
        cacheSpeed: results[32],
        deinterlace: results[33],
        toneMapping: results[34],
        videoSync: results[35],
        interpolation: results[36],
        tscale: results[37],
        targetColorspaceHint: results[38],
        cpuUsage: cpuUsage,
        gpuStats: gpuStats,
      );
    });
  }

  // ── CPU via /proc/stat ──────────────────────────────────────────────────────

  Future<double?> _readCpuUsage() async {
    if (kIsWeb || !Platform.isLinux) return null;
    try {
      final lines = await File('/proc/stat').readAsLines();
      final cpu = lines.firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
      if (cpu.isEmpty) return null;
      final nums = cpu.split(RegExp(r'\s+')).skip(1).map(int.tryParse).whereType<int>().toList();
      if (nums.length < 4) return null;
      // idle = idle + iowait (index 3 + 4)
      final idle = nums[3] + (nums.length > 4 ? nums[4] : 0);
      final total = nums.reduce((a, b) => a + b);
      final prev = (_prevCpuIdle, _prevCpuTotal);
      _prevCpuIdle = idle;
      _prevCpuTotal = total;
      if (prev.$1 == null || prev.$2 == null) return null;
      final dTotal = total - prev.$2!;
      if (dTotal == 0) return 0;
      return (1.0 - (idle - prev.$1!) / dTotal) * 100;
    } catch (_) {
      return null;
    }
  }

  // ── GPU: sysfs (AMD/Intel) then nvidia-smi (NVIDIA) ────────────────────────

  Future<_GpuStats?> _readGpuStats() async {
    if (kIsWeb || !Platform.isLinux) return null;

    // Try sysfs first — works for AMD and Intel
    final sysfsStats = await _readGpuSysfs();
    if (sysfsStats != null) return sysfsStats;

    // Fall back to nvidia-smi
    return _readNvidiaSmi();
  }

  Future<_GpuStats?> _readGpuSysfs() async {
    try {
      final cards = Directory('/sys/class/drm')
          .listSync()
          .whereType<Link>()
          .where((e) => RegExp(r'card\d+$').hasMatch(e.path.split('/').last))
          .map((e) => e.path)
          .toList()
        ..sort();

      int? bestUtil;
      int? bestTemp;
      int? vramUsed;
      int? vramTotal;

      for (final card in cards) {
        final base = '$card/device';
        final utilFile = File('$base/gpu_busy_percent');
        if (!utilFile.existsSync()) continue;
        final util = int.tryParse((await utilFile.readAsString()).trim());
        if (util == null) continue;
        if (bestUtil == null || util > bestUtil) {
          bestUtil = util;
          // Optional: temperature
          final tempFile = File('$base/hwmon/hwmon0/temp1_input');
          if (tempFile.existsSync()) {
            final raw = int.tryParse((await tempFile.readAsString()).trim());
            if (raw != null) bestTemp = raw ~/ 1000;
          }
          // VRAM via memory_info
          final memFile = File('$base/mem_info_vram_used');
          final memTotalFile = File('$base/mem_info_vram_total');
          if (memFile.existsSync() && memTotalFile.existsSync()) {
            final used = int.tryParse((await memFile.readAsString()).trim());
            final total = int.tryParse((await memTotalFile.readAsString()).trim());
            if (used != null) vramUsed = used ~/ (1024 * 1024);
            if (total != null) vramTotal = total ~/ (1024 * 1024);
          }
        }
      }

      if (bestUtil == null) return null;
      return _GpuStats(utilization: bestUtil, temperature: bestTemp, vramUsedMb: vramUsed, vramTotalMb: vramTotal);
    } catch (_) {
      return null;
    }
  }

  Future<_GpuStats?> _readNvidiaSmi() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total',
        '--format=csv,noheader,nounits',
      ], runInShell: false).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return null;
      final parts = (result.stdout as String).trim().split(',').map((s) => s.trim()).toList();
      if (parts.length < 4) return null;
      return _GpuStats(
        utilization: int.tryParse(parts[0]),
        temperature: int.tryParse(parts[1]),
        vramUsedMb: int.tryParse(parts[2]),
        vramTotalMb: int.tryParse(parts[3]),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(showVideoStatsProvider);
    if (!visible) return const SizedBox.shrink();

    return Positioned(
      top: 16,
      left: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _section('FILE'),
                _row('Title', _title),
                _row('Format', _stats.fileFormat),
                _row('Size', _fileSizeLabel),
                _row('Duration', _durationLabel),
                const SizedBox(height: 4),
                _section('VIDEO'),
                _row('Codec', _stats.videoCodec),
                _row('Decode', _hwdecLabel),
                if (_stats.deinterlace == 'yes') _row('Deinterlace', 'on'),
                _row('Tone map', _stats.toneMapping),
                _row('Input', _inputRes),
                _row('Output', _outputRes),
                _row('FPS', _fps),
                _row('Pixel fmt', _stats.pixelFormat),
                if (_isHdr) _row('HDR', _hdrLabel),
                _row('Bitrate', _bitrateLabel(_stats.videoBitrate)),
                const SizedBox(height: 4),
                _section('AUDIO'),
                _row('Codec', _stats.audioCodec),
                _row('Channels', _stats.audioChannels),
                _row('Sample rate', _sampleRateLabel),
                _row('Bitrate', _bitrateLabel(_stats.audioBitrate)),
                const SizedBox(height: 4),
                _section('DISPLAY'),
                _row('VO', _stats.currentVo),
                _row('Refresh', _displayFpsLabel),
                _row('Out fmt', _stats.outPixelFormat),
                _row('Video sync', _stats.videoSync),
                if (_stats.interpolation == 'yes') _row('Interpolation', _stats.tscale ?? 'on'),
                if (_stats.targetColorspaceHint == 'yes') _row('CS hint', 'on'),
                const SizedBox(height: 4),
                _section('SYSTEM'),
                _row('CPU', _cpuLabel),
                _row('GPU', _gpuLabel),
                if (_stats.gpuStats?.temperature != null) _row('GPU temp', '${_stats.gpuStats!.temperature}°C'),
                if (_vramLabel != null) _row('VRAM', _vramLabel!),
                const SizedBox(height: 4),
                _section('PERFORMANCE'),
                _row('A/V sync', _avSyncLabel),
                _row('Dropped', _dropLabel),
                _row('Vsync ratio', _vsyncLabel),
                if (_hasCacheData) _row('Cache', _cacheLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: Color(0xFFAAAAAA))),
        ),
        Flexible(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  // ── Formatters ──────────────────────────────────────────────────────────────

  String? get _title {
    final t = _stats.mediaTitle;
    final f = _stats.filename;
    final label = (t?.isNotEmpty == true && t != f) ? t : f;
    if (label == null) return null;
    return label.length > 50 ? '${label.substring(0, 47)}…' : label;
  }

  String? get _fileSizeLabel {
    final bytes = double.tryParse(_stats.fileSize ?? '');
    if (bytes == null) return null;
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String? get _durationLabel {
    final secs = double.tryParse(_stats.duration ?? '')?.toInt();
    if (secs == null) return null;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String? get _inputRes {
    if (_stats.width == null || _stats.height == null) return null;
    return '${_stats.width}×${_stats.height}';
  }

  String? get _outputRes {
    if (_stats.outWidth == null || _stats.outHeight == null) return null;
    final out = '${_stats.outWidth}×${_stats.outHeight}';
    return out == _inputRes ? null : out;
  }

  String? get _fps {
    final vf = _stats.vfFps;
    final cf = _stats.containerFps;
    if (vf == null) return cf;
    if (cf != null && vf != cf) return '$vf (container: $cf)';
    return vf;
  }

  bool get _isHdr {
    final g = _stats.gamma?.toLowerCase() ?? '';
    return g == 'pq' || g == 'hlg' || g.contains('2084') || g.contains('2100');
  }

  String get _hdrLabel {
    final g = _stats.gamma?.toLowerCase() ?? '';
    final p = _stats.primaries?.toLowerCase() ?? '';
    if (g == 'pq' || g.contains('2084')) return 'HDR10${p.contains('2020') ? ' (BT.2020)' : ''}';
    if (g == 'hlg') return 'HLG${p.contains('2020') ? ' (BT.2020)' : ''}';
    return _stats.gamma ?? '';
  }

  String? get _sampleRateLabel {
    final hz = int.tryParse(_stats.sampleRate ?? '');
    if (hz == null) return null;
    return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';
  }

  String? get _displayFpsLabel {
    final raw = _stats.displayFps ?? _stats.estimatedDisplayFps;
    if (raw == null) return null;
    final hz = double.tryParse(raw);
    return hz != null ? '${hz.toStringAsFixed(3)} Hz' : raw;
  }

  String? get _cpuLabel {
    final v = _stats.cpuUsage;
    if (v == null) return null;
    return '${v.toStringAsFixed(1)}%';
  }

  String? get _gpuLabel {
    final g = _stats.gpuStats;
    if (g?.utilization == null) return null;
    return '${g!.utilization}%';
  }

  String? get _vramLabel {
    final g = _stats.gpuStats;
    if (g?.vramUsedMb == null || g?.vramTotalMb == null) return null;
    return '${g!.vramUsedMb} / ${g.vramTotalMb} MB';
  }

  String? get _avSyncLabel {
    final ms = double.tryParse(_stats.avSync ?? '');
    if (ms == null) return null;
    return '${(ms * 1000).toStringAsFixed(1)} ms';
  }

  String? get _dropLabel {
    final d = int.tryParse(_stats.dropCount ?? '0') ?? 0;
    final dd = int.tryParse(_stats.decoderDropCount ?? '0') ?? 0;
    final vo = int.tryParse(_stats.voDropCount ?? '0') ?? 0;
    final mt = int.tryParse(_stats.mistimedCount ?? '0') ?? 0;
    if (d == 0 && dd == 0 && vo == 0 && mt == 0) return '0';
    final parts = <String>[];
    if (d > 0) parts.add('total: $d');
    if (dd > 0) parts.add('dec: $dd');
    if (vo > 0) parts.add('vo: $vo');
    if (mt > 0) parts.add('mistimed: $mt');
    return parts.join(' | ');
  }

  String? get _vsyncLabel {
    final ratio = double.tryParse(_stats.vsyncRatio ?? '');
    return ratio != null ? ratio.toStringAsFixed(3) : null;
  }

  bool get _hasCacheData {
    final dur = double.tryParse(_stats.cacheDuration ?? '');
    final spd = double.tryParse(_stats.cacheSpeed ?? '');
    return (dur != null && dur > 0) || (spd != null && spd > 0);
  }

  String? get _cacheLabel {
    final parts = <String>[];
    final dur = double.tryParse(_stats.cacheDuration ?? '');
    final spd = double.tryParse(_stats.cacheSpeed ?? '');
    if (dur != null && dur > 0) parts.add('${dur.toStringAsFixed(1)}s buffered');
    if (spd != null && spd > 0) parts.add(_bitrateLabel(spd.toString()) ?? '');
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String? _bitrateLabel(String? raw) {
    final bps = double.tryParse(raw ?? '');
    if (bps == null) return raw;
    if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(1)} Mbps';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} kbps';
    return '${bps.toStringAsFixed(0)} bps';
  }

  String? get _hwdecLabel {
    final raw = _stats.hwdec;
    if (raw == null || raw == 'no') return 'software';
    return raw;
  }
}

// ── Data classes ────────────────────────────────────────────────────────────

class _GpuStats {
  final int? utilization;
  final int? temperature;
  final int? vramUsedMb;
  final int? vramTotalMb;

  const _GpuStats({this.utilization, this.temperature, this.vramUsedMb, this.vramTotalMb});
}

class _Stats {
  final String? videoCodec;
  final String? hwdec;
  final String? width;
  final String? height;
  final String? vfFps;
  final String? containerFps;
  final String? pixelFormat;
  final String? gamma;
  final String? primaries;
  final String? audioCodec;
  final String? audioChannels;
  final String? sampleRate;
  final String? audioBitrate;
  final String? currentVo;
  final String? displayFps;
  final String? estimatedDisplayFps;
  final String? outWidth;
  final String? outHeight;
  final String? outPixelFormat;
  final String? mediaTitle;
  final String? filename;
  final String? fileFormat;
  final String? fileSize;
  final String? duration;
  final String? videoBitrate;
  final String? avSync;
  final String? dropCount;
  final String? decoderDropCount;
  final String? voDropCount;
  final String? mistimedCount;
  final String? vsyncRatio;
  final String? cacheDuration;
  final String? cacheSpeed;
  final String? deinterlace;
  final String? toneMapping;
  final String? videoSync;
  final String? interpolation;
  final String? tscale;
  final String? targetColorspaceHint;
  final double? cpuUsage;
  final _GpuStats? gpuStats;

  const _Stats({
    this.videoCodec,
    this.hwdec,
    this.width,
    this.height,
    this.vfFps,
    this.containerFps,
    this.pixelFormat,
    this.gamma,
    this.primaries,
    this.audioCodec,
    this.audioChannels,
    this.sampleRate,
    this.audioBitrate,
    this.currentVo,
    this.displayFps,
    this.estimatedDisplayFps,
    this.outWidth,
    this.outHeight,
    this.outPixelFormat,
    this.mediaTitle,
    this.filename,
    this.fileFormat,
    this.fileSize,
    this.duration,
    this.videoBitrate,
    this.avSync,
    this.dropCount,
    this.decoderDropCount,
    this.voDropCount,
    this.mistimedCount,
    this.vsyncRatio,
    this.cacheDuration,
    this.cacheSpeed,
    this.deinterlace,
    this.toneMapping,
    this.videoSync,
    this.interpolation,
    this.tscale,
    this.targetColorspaceHint,
    this.cpuUsage,
    this.gpuStats,
  });
}
