import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('compressedVideos');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CompressPro',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.grey[700],
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[700],
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.grey),
        ),
      ),
      home: const VideoCompressorHome(),
    );
  }
}

class VideoCompressorHome extends StatefulWidget {
  const VideoCompressorHome({super.key});

  @override
  _VideoCompressorHomeState createState() => _VideoCompressorHomeState();
}

class _VideoCompressorHomeState extends State<VideoCompressorHome>
    with TickerProviderStateMixin {
  File? _originalVideo;
  File? _compressedVideo;
  VideoPlayerController? _videoController;
  bool _isCompressing = false;
  double _compressionProgress = 0.0;
  late AnimationController _compressionAnimationController;
  late Animation<double> _compressionAnimation;
  Subscription? _compressionProgressSubscription;

  @override
  void initState() {
    super.initState();
    _compressionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _compressionAnimation = CurvedAnimation(
      parent: _compressionAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _compressionAnimationController.dispose();
    _compressionProgressSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _pickAndCompressVideo() async {
    if (_isCompressing) {
      Fluttertoast.showToast(msg: "Already compressing a video!");
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() {
      _originalVideo = File(pickedFile.path);
      _isCompressing = true;
      _compressionProgress = 0.0;
      _compressedVideo = null;
      _videoController?.dispose();
      _videoController = null;
    });

    _initializeVideoPlayer(_originalVideo!);

    try {
      _compressionProgressSubscription =
          VideoCompress.compressProgress$.subscribe((progress) {
        setState(() {
          _compressionProgress = progress / 100;
        });
      });

      final mediaInfo = await VideoCompress.compressVideo(
        _originalVideo!.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      if (mediaInfo != null && mediaInfo.file != null) {
        _compressedVideo = mediaInfo.file!;
        await _saveCompressedVideo();
        _compressionAnimationController.forward();
      }
    } catch (e) {
      _showErrorDialog('Compression failed. Please try again.');
    } finally {
      setState(() {
        _isCompressing = false;
      });
    }
  }

  Future<void> _saveCompressedVideo() async {
    try {
      final directory = await getExternalStorageDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final savedPath =
          path.join(directory!.path, 'compressed_video_$timestamp.mp4');
      await _compressedVideo!.copy(savedPath);

      final thumbnail = await VideoCompress.getFileThumbnail(
        _compressedVideo!.path,
        quality: 50,
      );

      final box = Hive.box('compressedVideos');
      await box.add({
        'path': savedPath,
        'thumbnail': thumbnail.path,
        'originalSize': _originalVideo!.lengthSync(),
        'compressedSize': _compressedVideo!.lengthSync(),
        'timestamp': timestamp,
      });

      _showSuccessDialog('Video compressed and saved successfully!');
    } catch (e) {
      _showErrorDialog('Failed to save the video. Please try again.');
    }
  }

  void _initializeVideoPlayer(File videoFile) {
    _videoController = VideoPlayerController.file(videoFile)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  void _resetState() {
    setState(() {
      _originalVideo = null;
      _compressedVideo = null;
      _videoController?.dispose();
      _videoController = null;
      _isCompressing = false;
      _compressionProgress = 0.0;
      _compressionAnimationController.reset();
      _compressionProgressSubscription?.unsubscribe();
      _compressionProgressSubscription = null;
    });
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            'Success',
            style: TextStyle(color: Colors.green, fontSize: 18),
          ),
          content: Text(message, style: const TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              child: const Text('OK', style: TextStyle(color: Colors.green)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            'Error',
            style: TextStyle(color: Colors.red, fontSize: 18),
          ),
          content: Text(message, style: const TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              child: const Text('OK', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareVideo(File video) async {
    try {
      final result = await Share.shareXFiles([XFile(video.path)]);
      if (result.status == ShareResultStatus.success) {
        Fluttertoast.showToast(msg: "Video shared successfully!");
      } else if (result.status == ShareResultStatus.dismissed) {
        // Do nothing if the share action is dismissed
      }
    } catch (e) {
      _showErrorDialog('Failed to share the video. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CompressPro',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.grey),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CompressedVideosPage()),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildVideoPlayerSection(),
              const SizedBox(height: 20),
              _buildCompressionSection(),
              const SizedBox(height: 20),
              _buildStatsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayerSection() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      return Column(
        children: [
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
          VideoProgressIndicator(_videoController!, allowScrubbing: true),
          IconButton(
            iconSize: 30,
            icon: Icon(
              _videoController!.value.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _videoController!.value.isPlaying
                    ? _videoController!.pause()
                    : _videoController!.play();
              });
            },
          ),
        ],
      );
    } else {
      return Container();
    }
  }

  Widget _buildCompressionSection() {
    if (_isCompressing) {
      return Column(
        children: [
          CircularProgressIndicator(value: _compressionProgress),
          const SizedBox(height: 10),
          Text(
            'Compressing: ${(_compressionProgress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      );
    } else if (_originalVideo == null) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.video_library),
        label: const Text(
          'Select and Compress Video',
          style: TextStyle(color: Colors.black),
        ),
        onPressed: _pickAndCompressVideo,
      );
    } else {
      return Container();
    }
  }

  Widget _buildStatsSection() {
    if (_compressedVideo != null) {
      final originalSize = _originalVideo!.lengthSync();
      final compressedSize = _compressedVideo!.lengthSync();
      final reductionPercent = 100 - ((compressedSize / originalSize) * 100);

      return FadeTransition(
        opacity: _compressionAnimation,
        child: Column(
          children: [
            Card(
              color: Colors.grey[800],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Compression Summary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSummaryRow(
                      'Original Size',
                      '${(originalSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                    ),
                    _buildSummaryRow(
                      'Compressed Size',
                      '${(compressedSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                    ),
                    _buildSummaryRow(
                      'Reduction',
                      '${reductionPercent.toStringAsFixed(2)}%',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.share, size: 30, color: Colors.grey),
                  onPressed: () => _shareVideo(_compressedVideo!),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.save, size: 30, color: Colors.grey),
                  onPressed: () => GallerySaver.saveVideo(_compressedVideo!.path)
                      .then((_) => Fluttertoast.showToast(
                          msg: "Video saved to gallery!")),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.home, size: 30, color: Colors.grey),
                  onPressed: _resetState,
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return Container();
    }
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$label: ', style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

class CompressedVideosPage extends StatelessWidget {
  const CompressedVideosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('compressedVideos');
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Compressed Videos',
          style: TextStyle(color: Colors.grey),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box box, _) {
          if (box.isEmpty) {
            return const Center(
              child: Text(
                'No videos compressed yet.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }
          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final videoData = box.getAt(index);
              return Slidable(
                endActionPane: ActionPane(
                  motion: const ScrollMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (_) {
                        box.deleteAt(index);
                        File(videoData['path']).delete();
                        Fluttertoast.showToast(msg: "Video deleted!");
                      },
                      backgroundColor: Colors.red,
                      icon: Icons.delete,
                      label: 'Delete',
                    ),
                  ],
                ),
                child: ListTile(
                  leading: Image.file(
                    File(videoData['thumbnail']),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                  title: Text(
                    'Compressed on ${videoData['timestamp']}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  subtitle: Text(
                    'Original: ${(videoData['originalSize'] / (1024 * 1024)).toStringAsFixed(2)} MB, '
                    'Compressed: ${(videoData['compressedSize'] / (1024 * 1024)).toStringAsFixed(2)} MB',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () async {
                    final videoFile = File(videoData['path']);
                    await _playVideoFullScreen(context, videoFile);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.grey),
                        onPressed: () async {
                          final videoFile = File(videoData['path']);
                          await Share.shareXFiles([XFile(videoFile.path)]);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.save, color: Colors.grey),
                        onPressed: () async {
                          final videoFile = File(videoData['path']);
                          await GallerySaver.saveVideo(videoFile.path);
                          Fluttertoast.showToast(msg: "Video saved to gallery!");
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _playVideoFullScreen(
      BuildContext context, File videoFile) async {
    final videoController = VideoPlayerController.file(videoFile);
    await videoController.initialize();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: AspectRatio(
              aspectRatio: videoController.value.aspectRatio,
              child: VideoPlayer(videoController),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              if (videoController.value.isPlaying) {
                videoController.pause();
              } else {
                videoController.play();
              }
            },
            backgroundColor: Colors.grey,
            child: Icon(
              videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.black,
            ),
          ),
        ),
      ),
    ).then((_) {
      videoController.dispose();
    });
  }
}