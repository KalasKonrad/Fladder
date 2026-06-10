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
      p('video-codec'),
      p('hwdec-current'),
      p('video-params/w'),
      p('video-params/h'),
      p('estimated-vf-fps'),
      p('container-fps'),
      p('video-params/pixelformat'),
      p('video-params/gamma'),
      p('video-params/primaries'),
      p('video-params/colormatrix'),
      p('audio-codec'),
      p('audio-params/hr-channels'),
      p('audio-params/samplerate'),
      p('avsync'),
      p('frame-drop-count'),
      p('decoder-frame-drop-count'),
      p('video-bitrate'),
      p('audio-bitrate'),
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
        colorMatrix: results[9],
        audioCodec: results[10],
        audioChannels: results[11],
        sampleRate: results[12],
        avSync: results[13],
        dropCount: results[14],
        decoderDropCount: results[15],
        videoBitrate: results[16],
        audioBitrate: results[17],
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
                _section('VIDEO'),
                _row('Codec', _stats.videoCodec),
                _row('Decode', _hwdecLabel(_stats.hwdec)),
                _row('Resolution', _resolution),
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
                _section('PERFORMANCE'),
                _row('A/V sync', _avSyncLabel),
                _row('Dropped', _dropLabel),
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
        Text(value),
      ],
    );
  }

  String? get _resolution {
    if (_stats.width == null || _stats.height == null) return null;
    return '${_stats.width}×${_stats.height}';
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
    final sr = _stats.sampleRate;
    if (sr == null) return null;
    final hz = int.tryParse(sr);
    if (hz == null) return sr;
    return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';
  }

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
    if (d == 0 && dd == 0) return '0';
    return '$d (decoder: $dd)';
  }

  String? _bitrateLabel(String? raw) {
    if (raw == null) return null;
    final bps = double.tryParse(raw);
    if (bps == null) return raw;
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} kbps';
    return '${bps.toStringAsFixed(0)} bps';
  }

  String? _hwdecLabel(String? raw) {
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
  final String? colorMatrix;
  final String? audioCodec;
  final String? audioChannels;
  final String? sampleRate;
  final String? avSync;
  final String? dropCount;
  final String? decoderDropCount;
  final String? videoBitrate;
  final String? audioBitrate;

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
    this.colorMatrix,
    this.audioCodec,
    this.audioChannels,
    this.sampleRate,
    this.avSync,
    this.dropCount,
    this.decoderDropCount,
    this.videoBitrate,
    this.audioBitrate,
  });
}
