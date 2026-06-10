import 'dart:async';

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

    final results = await Future.wait([
      // Video
      p('video-codec'),
      p('hwdec-current'),
      p('video-params/w'),
      p('video-params/h'),
      p('estimated-vf-fps'),
      p('container-fps'),
      p('video-params/pixelformat'),
      p('video-params/gamma'),
      p('video-params/primaries'),
      // Audio
      p('audio-codec'),
      p('audio-params/hr-channels'),
      p('audio-params/samplerate'),
      p('audio-bitrate'),
      // Display
      p('current-vo'),
      p('display-fps'),
      p('estimated-display-fps'),
      p('video-out-params/w'),
      p('video-out-params/h'),
      p('video-out-params/pixelformat'),
      // File
      p('media-title'),
      p('filename'),
      p('file-format'),
      p('file-size'),
      p('duration'),
      p('video-bitrate'),
      // Performance
      p('avsync'),
      p('frame-drop-count'),
      p('decoder-frame-drop-count'),
      p('vo-drop-frame-count'),
      p('mistimed-frame-count'),
      p('vsync-ratio'),
      p('demuxer-cache-duration'),
      p('cache-speed'),
    ]);

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
      );
    });
  }

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
                // File
                _section('FILE'),
                _row('Title', _title),
                _row('Format', _stats.fileFormat),
                _row('Size', _fileSizeLabel),
                _row('Duration', _durationLabel),

                const SizedBox(height: 4),

                // Video
                _section('VIDEO'),
                _row('Codec', _stats.videoCodec),
                _row('Decode', _hwdecLabel),
                _row('Input', _inputRes),
                _row('Output', _outputRes),
                _row('FPS', _fps),
                _row('Pixel fmt', _stats.pixelFormat),
                if (_isHdr) _row('HDR', _hdrLabel),
                _row('Bitrate', _bitrateLabel(_stats.videoBitrate)),

                const SizedBox(height: 4),

                // Audio
                _section('AUDIO'),
                _row('Codec', _stats.audioCodec),
                _row('Channels', _stats.audioChannels),
                _row('Sample rate', _sampleRateLabel),
                _row('Bitrate', _bitrateLabel(_stats.audioBitrate)),

                const SizedBox(height: 4),

                // Display
                _section('DISPLAY'),
                _row('VO', _stats.currentVo),
                _row('Refresh', _displayFpsLabel),
                _row('Out fmt', _stats.outPixelFormat),

                const SizedBox(height: 4),

                // Performance
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

  // --- File ---

  String? get _title {
    final t = _stats.mediaTitle;
    final f = _stats.filename;
    final label = (t?.isNotEmpty == true && t != f) ? t : f;
    if (label == null) return null;
    return label.length > 50 ? '${label.substring(0, 47)}…' : label;
  }

  String? get _fileSizeLabel {
    final raw = _stats.fileSize;
    if (raw == null) return null;
    final bytes = double.tryParse(raw);
    if (bytes == null) return raw;
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String? get _durationLabel {
    final raw = _stats.duration;
    if (raw == null) return null;
    final secs = double.tryParse(raw)?.toInt();
    if (secs == null) return raw;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  // --- Video ---

  String? get _inputRes {
    if (_stats.width == null || _stats.height == null) return null;
    return '${_stats.width}×${_stats.height}';
  }

  String? get _outputRes {
    if (_stats.outWidth == null || _stats.outHeight == null) return null;
    final out = '${_stats.outWidth}×${_stats.outHeight}';
    if (out == _inputRes) return null; // skip if same as input
    return out;
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

  // --- Audio ---

  String? get _sampleRateLabel {
    final sr = _stats.sampleRate;
    if (sr == null) return null;
    final hz = int.tryParse(sr);
    if (hz == null) return sr;
    return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';
  }

  // --- Display ---

  String? get _displayFpsLabel {
    final d = _stats.displayFps;
    final e = _stats.estimatedDisplayFps;
    if (d == null && e == null) return null;
    final main = d ?? e!;
    final hz = double.tryParse(main);
    final label = hz != null ? '${hz.toStringAsFixed(3)} Hz' : main;
    return label;
  }

  // --- Performance ---

  String? get _avSyncLabel {
    final v = _stats.avSync;
    if (v == null) return null;
    final ms = double.tryParse(v);
    if (ms == null) return v;
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
    final v = _stats.vsyncRatio;
    if (v == null) return null;
    final ratio = double.tryParse(v);
    if (ratio == null) return v;
    return ratio.toStringAsFixed(3);
  }

  bool get _hasCacheData {
    final dur = double.tryParse(_stats.cacheDuration ?? '');
    final spd = double.tryParse(_stats.cacheSpeed ?? '');
    return (dur != null && dur > 0) || (spd != null && spd > 0);
  }

  String? get _cacheLabel {
    final dur = double.tryParse(_stats.cacheDuration ?? '');
    final spd = double.tryParse(_stats.cacheSpeed ?? '');
    final parts = <String>[];
    if (dur != null && dur > 0) parts.add('${dur.toStringAsFixed(1)}s buffered');
    if (spd != null && spd > 0) parts.add(_bitrateLabel(spd.toString()) ?? '');
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String? _bitrateLabel(String? raw) {
    if (raw == null) return null;
    final bps = double.tryParse(raw);
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
  });
}
