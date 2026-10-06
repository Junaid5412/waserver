import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String title;
  final String documentUrl;
  final Map<String, String> headers;
  final String? filename;
  final String? mimetype;

  const DocumentViewerScreen({
    super.key,
    required this.title,
    required this.documentUrl,
    required this.headers,
    this.filename,
    this.mimetype,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _localFilePath;
  int _fileSizeBytes = 0;
  bool _isDownloaded = false;

  // Document types
  bool _isPdf = false;
  bool _isExcel = false;
  bool _isWord = false;
  bool _isText = false;

  // PDF specific
  int _totalPages = 0;
  int _currentPage = 0;

  // Spreadsheet specific
  List<List<String>> _sheetData = [];
  String _searchQuery = '';

  // Word/Text specific
  String _extractedText = '';

  @override
  void initState() {
    super.initState();
    _detectFileType();
    _downloadAndPrepareDocument();
  }

  void _detectFileType() {
    final name = (widget.filename ?? widget.title).toLowerCase();
    final mime = (widget.mimetype ?? '').toLowerCase();

    if (name.endsWith('.pdf') || mime == 'application/pdf') {
      _isPdf = true;
    } else if (name.endsWith('.xlsx') || name.endsWith('.xls') || name.endsWith('.csv') || mime.contains('spreadsheet') || mime.contains('excel')) {
      _isExcel = true;
    } else if (name.endsWith('.docx') || name.endsWith('.doc') || mime.contains('word') || mime.contains('officedocument.wordprocessingml')) {
      _isWord = true;
    } else {
      _isText = true;
    }
  }

  Future<void> _downloadAndPrepareDocument() async {
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
        final safeName = (widget.filename ?? 'document').replaceAll(RegExp(r'[^\w.-]'), '_');
        final file = File('${dir.path}/doc_${DateTime.now().millisecondsSinceEpoch}_$safeName');
        await file.writeAsBytes(bytes);

        if (_isExcel) {
          _parseSpreadsheet(bytes);
        } else if (_isWord) {
          _parseWordDocument(bytes);
        } else if (_isText) {
          try {
            _extractedText = utf8.decode(bytes, allowMalformed: true);
          } catch (_) {
            _extractedText = String.fromCharCodes(bytes);
          }
        }

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

  void _parseSpreadsheet(List<int> bytes) {
    // 1. Try OpenXML (.xlsx) parsing first
    if (bytes.length > 30 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) {
      try {
        final entries = _extractZipEntries(bytes);

        // Extract shared strings
        final sst = <String>[];
        final sstBytes = entries['xl/sharedstrings.xml'];
        if (sstBytes != null) {
          final sstXml = utf8.decode(sstBytes, allowMalformed: true);
          final siRegex = RegExp(r'<si>(.*?)</si>', dotAll: true);
          for (final m in siRegex.allMatches(sstXml)) {
            final tMatches = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(m.group(1) ?? '');
            final combined = tMatches.map((tm) => _unescapeXml(tm.group(1) ?? '')).join('');
            sst.add(combined);
          }
        }

        // Find first worksheet xml (e.g. xl/worksheets/sheet1.xml)
        String? sheetKey;
        for (final k in entries.keys) {
          if (k.startsWith('xl/worksheets/sheet') && k.endsWith('.xml')) {
            sheetKey = k;
            break;
          }
        }

        if (sheetKey != null && entries[sheetKey] != null) {
          final sheetXml = utf8.decode(entries[sheetKey]!, allowMalformed: true);
          final rowRegex = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true);
          final rows = <List<String>>[];

          for (final rMatch in rowRegex.allMatches(sheetXml)) {
            final rowContent = rMatch.group(1) ?? '';
            final cRegex = RegExp(r'<c\s+r="([A-Z]+)\d+"([^>]*)>(.*?)</c>', dotAll: true);
            final row = <String>[];

            for (final cMatch in cRegex.allMatches(rowContent)) {
              final colStr = cMatch.group(1) ?? 'A';
              final colIdx = _colToIdx(colStr);
              final attrs = cMatch.group(2) ?? '';
              final body = cMatch.group(3) ?? '';

              String val = '';
              if (attrs.contains('t="s"')) {
                final vMatch = RegExp(r'<v>(\d+)</v>').firstMatch(body);
                if (vMatch != null) {
                  final sstIdx = int.tryParse(vMatch.group(1) ?? '') ?? -1;
                  if (sstIdx >= 0 && sstIdx < sst.length) {
                    val = sst[sstIdx];
                  }
                }
              } else if (attrs.contains('t="inlineStr"')) {
                final tMatch = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).firstMatch(body);
                if (tMatch != null) val = _unescapeXml(tMatch.group(1) ?? '');
              } else if (attrs.contains('t="b"')) {
                final vMatch = RegExp(r'<v>(\d+)</v>').firstMatch(body);
                val = (vMatch?.group(1) == '1') ? 'TRUE' : 'FALSE';
              } else {
                final vMatch = RegExp(r'<v>(.*?)</v>').firstMatch(body);
                if (vMatch != null) val = _unescapeXml(vMatch.group(1) ?? '');
              }

              while (row.length < colIdx) {
                row.add('');
              }
              if (colIdx < row.length) {
                row[colIdx] = val;
              } else {
                row.add(val);
              }
            }

            if (row.any((cell) => cell.trim().isNotEmpty)) {
              rows.add(row);
            }
          }

          if (rows.isNotEmpty) {
            int maxCols = 0;
            for (final r in rows) {
              if (r.length > maxCols) maxCols = r.length;
            }
            maxCols = maxCols.clamp(1, 50);
            for (final r in rows) {
              while (r.length < maxCols) {
                r.add('');
              }
            }
            _sheetData = rows;
            return;
          }
        }
      } catch (_) {}
    }

    // 2. Try CSV / TSV text parsing
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split(RegExp(r'\r?\n'));
      final rows = <List<String>>[];

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        List<String> cols;
        if (line.contains('\t')) {
          cols = line.split('\t');
        } else if (line.contains(';')) {
          cols = line.split(';');
        } else {
          cols = _parseCsvLine(line);
        }
        rows.add(cols.map((c) => c.trim()).toList());
      }

      if (rows.isNotEmpty) {
        int maxCols = 0;
        for (final r in rows) {
          if (r.length > maxCols) maxCols = r.length;
        }
        maxCols = maxCols.clamp(1, 50);
        for (final r in rows) {
          while (r.length < maxCols) {
            r.add('');
          }
        }
        _sheetData = rows;
        return;
      }
    } catch (_) {}

    // 3. Fallback: extract visible text from binary
    _extractedText = _extractTextFromBinary(bytes);
    if (_extractedText.isEmpty) {
      _sheetData = [
        ['Spreadsheet File', widget.filename ?? 'Document.xlsx'],
        ['Size', _formatSize(bytes.length)],
        ['Status', 'Tap "Open in External App" to view in Microsoft Excel or Google Sheets'],
      ];
    }
  }

  Map<String, List<int>> _extractZipEntries(List<int> bytes) {
    final entries = <String, List<int>>{};
    if (bytes.length < 22) return entries;

    final bd = ByteData.sublistView(Uint8List.fromList(bytes));

    // 1. Search for End of Central Directory (0x06054b50) from the end
    int eocd = -1;
    for (int i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }

    if (eocd != -1) {
      final totalEntries = bd.getUint16(eocd + 10, Endian.little);
      final cdOffset = bd.getUint32(eocd + 16, Endian.little);
      int cdPos = cdOffset;

      for (int i = 0; i < totalEntries && cdPos < eocd; i++) {
        if (cdPos + 46 > bytes.length) break;
        if (bytes[cdPos] != 0x50 || bytes[cdPos + 1] != 0x4B || bytes[cdPos + 2] != 0x01 || bytes[cdPos + 3] != 0x02) {
          break;
        }

        final method = bd.getUint16(cdPos + 10, Endian.little);
        final compSize = bd.getUint32(cdPos + 20, Endian.little);
        final nameLen = bd.getUint16(cdPos + 28, Endian.little);
        final extraLen = bd.getUint16(cdPos + 30, Endian.little);
        final commentLen = bd.getUint16(cdPos + 32, Endian.little);
        final localOffset = bd.getUint32(cdPos + 42, Endian.little);

        if (cdPos + 46 + nameLen <= bytes.length) {
          final name = utf8.decode(bytes.sublist(cdPos + 46, cdPos + 46 + nameLen), allowMalformed: true).toLowerCase();

          if (localOffset + 30 <= bytes.length) {
            final locNameLen = bd.getUint16(localOffset + 26, Endian.little);
            final locExtraLen = bd.getUint16(localOffset + 28, Endian.little);
            final dataStart = localOffset + 30 + locNameLen + locExtraLen;

            if (dataStart + compSize <= bytes.length) {
              final compData = bytes.sublist(dataStart, dataStart + compSize);
              try {
                if (method == 8) {
                  entries[name] = ZLibDecoder(raw: true).convert(compData);
                } else if (method == 0) {
                  entries[name] = compData;
                }
              } catch (_) {}
            }
          }
        }
        cdPos += 46 + nameLen + extraLen + commentLen;
      }
    }

    // 2. Fallback: scan local headers if central directory was empty
    if (entries.isEmpty) {
      int pos = 0;
      while (pos < bytes.length - 30) {
        if (bytes[pos] == 0x50 && bytes[pos + 1] == 0x4B && bytes[pos + 2] == 0x03 && bytes[pos + 3] == 0x04) {
          final method = bd.getUint16(pos + 8, Endian.little);
          final compSize = bd.getUint32(pos + 18, Endian.little);
          final nameLen = bd.getUint16(pos + 26, Endian.little);
          final extraLen = bd.getUint16(pos + 28, Endian.little);

          if (pos + 30 + nameLen <= bytes.length) {
            final name = utf8.decode(bytes.sublist(pos + 30, pos + 30 + nameLen), allowMalformed: true).toLowerCase();
            final dataStart = pos + 30 + nameLen + extraLen;
            if (compSize > 0 && dataStart + compSize <= bytes.length) {
              final compData = bytes.sublist(dataStart, dataStart + compSize);
              try {
                if (method == 8) {
                  entries[name] = ZLibDecoder(raw: true).convert(compData);
                } else if (method == 0) {
                  entries[name] = compData;
                }
              } catch (_) {}
              pos = dataStart + compSize;
              continue;
            }
          }
        }
        pos++;
      }
    }
    return entries;
  }

  int _colToIdx(String colStr) {
    int idx = 0;
    for (int i = 0; i < colStr.length; i++) {
      idx = idx * 26 + (colStr.codeUnitAt(i) - 64);
    }
    return (idx - 1).clamp(0, 50);
  }

  String _unescapeXml(String xml) {
    return xml
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  List<String> _parseCsvLine(String line) {
    List<String> result = [];
    StringBuffer cur = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    result.add(cur.toString());
    return result;
  }

  void _parseWordDocument(List<int> bytes) {
    // 1. Try OpenXML (.docx) extraction
    if (bytes.length > 30 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) {
      try {
        final entries = _extractZipEntries(bytes);
        final docBytes = entries['word/document.xml'];
        if (docBytes != null) {
          final docXml = utf8.decode(docBytes, allowMalformed: true);
          final pRegex = RegExp(r'<w:p[^>]*>(.*?)</w:p>', dotAll: true);
          final paragraphs = <String>[];

          for (final pMatch in pRegex.allMatches(docXml)) {
            final pContent = pMatch.group(1) ?? '';
            final tMatches = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true).allMatches(pContent);
            final pText = tMatches.map((m) => _unescapeXml(m.group(1) ?? '')).join('');
            if (pText.trim().isNotEmpty) {
              paragraphs.add(pText.trim());
            }
          }

          if (paragraphs.isNotEmpty) {
            _extractedText = paragraphs.join('\n\n');
            return;
          }
        }
      } catch (_) {}
    }

    // 2. Binary text fallback
    final text = _extractTextFromBinary(bytes);
    if (text.isNotEmpty) {
      _extractedText = text;
    } else {
      _extractedText = 'Microsoft Word Document: ${widget.filename ?? "Document"}\n\nSize: ${_formatSize(bytes.length)}\n\nUse the buttons above to open in Microsoft Word / Google Docs or download to your device.';
    }
  }

  String _extractTextFromBinary(List<int> bytes) {
    try {
      final raw = utf8.decode(bytes, allowMalformed: true);
      final matches = RegExp(r'<w:t[^>]*>(.*?)</w:t>|<t[^>]*>(.*?)</t>').allMatches(raw);
      if (matches.isNotEmpty) {
        final sb = StringBuffer();
        for (final m in matches) {
          final t = m.group(1) ?? m.group(2) ?? '';
          if (t.isNotEmpty) sb.write('$t ');
        }
        final res = sb.toString().trim();
        if (res.isNotEmpty) return res;
      }

      // ASCII / printable fallback
      final printable = bytes.where((b) => (b >= 32 && b <= 126) || b == 10 || b == 13).toList();
      final str = String.fromCharCodes(printable);
      final clean = str.replaceAll(RegExp(r'\s{3,}'), '\n\n').trim();
      if (clean.length > 20) return clean;
    } catch (_) {}
    return '';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openExternal() async {
    if (_localFilePath == null) return;
    try {
      final uri = Uri.file(_localFilePath!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(Uri.parse(widget.documentUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open external viewer: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile() async {
    if (_localFilePath == null) return;
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/${widget.filename ?? "document"}';
      final file = File(_localFilePath!);
      await file.copy(savePath);

      if (mounted) {
        setState(() => _isDownloaded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: $savePath'),
            backgroundColor: WhatsAppTheme.primaryGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fileExt = (widget.filename ?? widget.title).split('.').last.toUpperCase();

    return Scaffold(
      backgroundColor: isDark ? WhatsAppTheme.bgDark : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_fileSizeBytes > 0)
              Text(
                '$fileExt • ${_formatSize(_fileSizeBytes)}${_isPdf && _totalPages > 0 ? " • $_totalPages pages" : ""}',
                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open with Device App',
            onPressed: _localFilePath != null ? _openExternal : null,
          ),
          IconButton(
            icon: Icon(_isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded),
            tooltip: 'Save to Device',
            onPressed: _localFilePath != null ? _downloadFile : null,
          ),
        ],
      ),
      body: _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
            const SizedBox(height: 16),
            Text(
              'Loading ${widget.filename ?? "document"}...',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 54),
              const SizedBox(height: 14),
              const Text('Unable to preview document', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? 'An error occurred', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _downloadAndPrepareDocument,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
              ),
            ],
          ),
        ),
      );
    }

    if (_isPdf && _localFilePath != null) {
      return Stack(
        children: [
          PDFView(
            filePath: _localFilePath!,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            backgroundColor: isDark ? WhatsAppTheme.bgDark : const Color(0xFFF0F2F5),
            onRender: (pages) => setState(() => _totalPages = pages ?? 0),
            onPageChanged: (page, total) => setState(() {
              _currentPage = (page ?? 0) + 1;
              _totalPages = total ?? 0;
            }),
          ),
          if (_totalPages > 0)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$_currentPage / $_totalPages',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      );
    }

    if (_isExcel && _sheetData.isNotEmpty) {
      return _buildSpreadsheetViewer(isDark);
    }

    // Word or Text content
    return _buildTextDocumentViewer(isDark);
  }

  Widget _buildSpreadsheetViewer(bool isDark) {
    final headerRow = _sheetData.first;
    final dataRows = _sheetData.length > 1 ? _sheetData.skip(1).toList() : <List<String>>[];
    final filteredDataRows = _searchQuery.isEmpty
        ? dataRows
        : dataRows.where((row) => row.any((c) => c.toLowerCase().contains(_searchQuery.toLowerCase()))).toList();

    return Column(
      children: [
        // Search & info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
          child: Column(
            children: [
              TextField(
                onChanged: (q) => setState(() => _searchQuery = q),
                decoration: InputDecoration(
                  hintText: 'Search in spreadsheet...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? Colors.black26 : const Color(0xFFF0F2F5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${dataRows.length} data rows • ${headerRow.length} columns',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (_localFilePath != null)
                    TextButton.icon(
                      onPressed: _openExternal,
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Open in Excel / Sheets', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Spreadsheet table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  isDark ? Colors.teal.shade900.withOpacity(0.5) : Colors.teal.shade50,
                ),
                columns: List.generate(
                  headerRow.length,
                  (index) => DataColumn(
                    label: Text(
                      headerRow[index].isNotEmpty ? headerRow[index] : 'Col ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                rows: filteredDataRows.map((row) {
                  return DataRow(
                    cells: List.generate(
                      headerRow.length,
                      (colIdx) => DataCell(
                        Text(colIdx < row.length ? row[colIdx] : ''),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextDocumentViewer(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isWord ? Icons.description_rounded : Icons.article_rounded,
                  color: _isWord ? Colors.blue.shade700 : WhatsAppTheme.primaryGreen,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.filename ?? 'Document Content',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            SelectableText(
              _extractedText.isNotEmpty ? _extractedText : 'No printable text found in this document.',
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF111B21),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
