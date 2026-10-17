import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Saves files into the app's external storage folder
/// (Android/data/<package>/files/Zelon), falling back to app documents.
class MediaDownload {
  static Future<Directory> _targetDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Zelon');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w.\- ]'), '_').trim();
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  /// Downloads [url] with [headers] and returns the saved file path.
  static Future<String> fromUrl(String url, Map<String, String> headers, String filename) async {
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Download failed (HTTP ${res.statusCode})');
    }
    final dir = await _targetDir();
    final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${_safeName(filename)}');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  /// Copies an already downloaded local file and returns the saved path.
  static Future<String> fromFile(String path, String filename) async {
    final dir = await _targetDir();
    final target = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${_safeName(filename)}';
    await File(path).copy(target);
    return target;
  }

  /// Picks a file extension from a mimetype for media without a filename.
  static String extensionFor(String? mimetype, String fallback) {
    final m = (mimetype ?? '').split(';').first.trim().toLowerCase();
    const map = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
      'video/mp4': 'mp4',
      'audio/ogg': 'ogg',
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'application/pdf': 'pdf',
    };
    return map[m] ?? fallback;
  }
}
