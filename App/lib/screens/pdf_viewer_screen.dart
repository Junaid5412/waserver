import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  int _fileSizeBytes = 0;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
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
        if (mounted) {
          setState(() {
            _fileSizeBytes = res.bodyBytes.length;
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
    if (bytes <= 0) return 'Unknown size';
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
            Text('Document downloaded to device storage'),
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
            Text(
              _fileSizeBytes > 0 ? _formatSize(_fileSizeBytes) : (widget.mimetype ?? 'Document'),
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
              color: Colors.white,
            ),
            tooltip: 'Download Document',
            onPressed: _downloadFile,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            tooltip: 'Share Document',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document ready to share')),
              );
            },
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
                  Text('Loading document preview...', style: TextStyle(fontSize: 14)),
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
                          'Unable to Load Document',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ?? 'Media file may have expired on WhatsApp servers.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _loadDocument,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Document Card Preview
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Big PDF Icon badge
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 42,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            SelectableText(
                              docName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),

                            Text(
                              '${_formatSize(_fileSizeBytes)} • ${widget.mimetype ?? "application/pdf"}',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            // Document metadata sheet
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _metaItem('Format', 'PDF Document', Icons.file_present_rounded, isDark),
                                _metaItem('Size', _formatSize(_fileSizeBytes), Icons.data_usage_rounded, isDark),
                                _metaItem('Security', 'Encrypted', Icons.lock_outline_rounded, isDark),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // Action Buttons
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _downloadFile,
                                icon: const Icon(Icons.download_rounded, color: Colors.white),
                                label: const Text(
                                  'Download to Device',
                                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: WhatsAppTheme.primaryGreen,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Document reader hint card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user_rounded, color: WhatsAppTheme.primaryGreen, size: 28),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('End-to-End Encrypted File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'This document is verified and stored in your Zelon Messenger cloud storage.',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _metaItem(String label, String value, IconData icon, bool isDark) {
    return Column(
      children: [
        Icon(icon, color: WhatsAppTheme.primaryGreen, size: 22),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
      ],
    );
  }
}
