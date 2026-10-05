import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/theme.dart';

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String documentUrl;
  final Map<String, String> headers;
  final String? filename;
  final String? mimetype;

  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.documentUrl,
    required this.headers,
    this.filename,
    this.mimetype,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _localFilePath;
  int _totalPages = 0;
  int _currentPage = 0;
  int _fileSizeBytes = 0;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _downloadAndPreparePdf();
  }

  Future<void> _downloadAndPreparePdf() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final res = await http.get(
        Uri.parse(widget.documentUrl),
        headers: widget.headers,
      );

      if (res.statusCode == 200) {
        final bytes = res.bodyBytes;
        final dir = await getTemporaryDirectory();
        final safeName = widget.filename?.replaceAll(RegExp(r'[^\w.-]'), '_') ?? 'document.pdf';
        final file = File('${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}_$safeName');
        await file.writeAsBytes(bytes);

        if (mounted) {
          setState(() {
            _localFilePath = file.path;
            _fileSizeBytes = bytes.length;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Server returned HTTP ${res.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _downloadFile() {
    setState(() => _isDownloaded = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text('PDF saved to device storage'),
          ],
        ),
        backgroundColor: WhatsAppTheme.primaryGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docName = widget.filename?.isNotEmpty == true
        ? widget.filename!
        : (widget.title.isNotEmpty ? widget.title : 'Document.pdf');

    return Scaffold(
      backgroundColor: isDark ? WhatsAppTheme.bgDark : const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              docName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                if (_totalPages > 0)
                  Text(
                    'Page ${_currentPage + 1} of $_totalPages',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                if (_totalPages > 0 && _fileSizeBytes > 0)
                  const Text(' • ', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
                if (_fileSizeBytes > 0)
                  Text(
                    _formatSize(_fileSizeBytes),
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
              color: Colors.white,
            ),
            tooltip: 'Save PDF',
            onPressed: _downloadFile,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
                  SizedBox(height: 16),
                  Text('Opening document inside app...', style: TextStyle(fontSize: 14)),
                ],
              ),
            )
          : _hasError
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 54, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        const Text(
                          'Unable to Render Document',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ?? 'PDF file could not be parsed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _downloadAndPreparePdf,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                        ),
                      ],
                    ),
                  ),
                )
              : _localFilePath != null
                  ? Stack(
                      children: [
                        PDFView(
                          filePath: _localFilePath!,
                          enableSwipe: true,
                          swipeHorizontal: false,
                          autoSpacing: true,
                          pageFling: true,
                          pageSnap: true,
                          defaultPage: _currentPage,
                          fitPolicy: FitPolicy.BOTH,
                          onRender: (pages) {
                            if (mounted) {
                              setState(() {
                                _totalPages = pages ?? 0;
                              });
                            }
                          },
                          onPageChanged: (page, total) {
                            if (mounted) {
                              setState(() {
                                _currentPage = page ?? 0;
                                _totalPages = total ?? 0;
                              });
                            }
                          },
                          onError: (error) {
                            if (mounted) {
                              setState(() {
                                _hasError = true;
                                _errorMessage = error.toString();
                              });
                            }
                          },
                        ),
                        // Page Floating Pill Indicator
                        if (_totalPages > 1)
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                              child: Text(
                                '${_currentPage + 1} / $_totalPages',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : const Center(child: Text('Document preview unavailable')),
    );
  }
}
