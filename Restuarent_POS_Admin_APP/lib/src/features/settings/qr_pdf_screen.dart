import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';

class QrPdfScreen extends StatefulWidget {
  const QrPdfScreen({super.key});

  @override
  State<QrPdfScreen> createState() => _QrPdfScreenState();
}

class _QrPdfScreenState extends State<QrPdfScreen> {
  final _urlCtrl = TextEditingController();
  bool _generating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_urlCtrl.text.isEmpty) {
      final app = AppScope.of(context);
      final baseUrl = app.cloudConfig.baseUrl.trim().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      if (baseUrl.isNotEmpty) {
        _urlCtrl.text = '$baseUrl/menu';
      } else {
        _urlCtrl.text = 'http://LOCAL_SERVER_IP:8000/menu';
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  String get _qrUrl {
    return _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<Uint8List> _qrBytes(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: ui.Color(0xFF1A1A2E),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: ui.Color(0xFF1A1A2E),
      ),
    );
    final image = await painter.toImage(512);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _generate() async {
    final url = _qrUrl;
    if (url.isEmpty) return;

    setState(() => _generating = true);
    try {
      final app = AppScope.of(context);
      final restaurantName = app.serverConfig.restaurantName.isEmpty
          ? 'Restaurant'
          : app.serverConfig.restaurantName;
      final outletName = app.serverConfig.outletName;

      final qrBytes = await _qrBytes(url);
      final qrImage = pw.MemoryImage(qrBytes);

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (_) => pw.Center(
            child: _pdfCard(
              restaurantName: restaurantName,
              outletName: outletName,
              qrImage: qrImage,
              url: url,
            ),
          ),
        ),
      );

      final bytes = await doc.save();
      if (!mounted) return;

      await Printing.layoutPdf(
        name: '${restaurantName.replaceAll(' ', '_')}_Menu_QR',
        onLayout: (_) async => bytes,
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  pw.Widget _pdfCard({
    required String restaurantName,
    required String outletName,
    required pw.ImageProvider qrImage,
    required String url,
  }) {
    const gold = PdfColor.fromInt(0xFFE8C547);
    const dark = PdfColor.fromInt(0xFF1A1A2E);
    const subtle = PdfColor.fromInt(0xFF6B7280);
    const bg = PdfColor.fromInt(0xFFFFFBF0);
    const line = PdfColor.fromInt(0xFFE5E7EB);

    return pw.Container(
      width: 340,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: line, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Brand dot
          pw.Container(
            width: 56,
            height: 56,
            decoration: pw.BoxDecoration(
              color: gold,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
            ),
            child: pw.Center(
              child: pw.Text(
                restaurantName.isNotEmpty
                    ? restaurantName[0].toUpperCase()
                    : 'R',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: dark,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            restaurantName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: dark,
            ),
          ),
          if (outletName.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              outletName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 11, color: subtle),
            ),
          ],
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: bg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: gold, width: 1.5),
            ),
            child: pw.Text(
              'স্ক্যান করে অর্ডার করুন  ·  Scan to Order',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: dark,
              ),
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              border: pw.Border.all(color: line, width: 1.5),
            ),
            child: pw.Image(
              qrImage,
              width: 200,
              height: 200,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            url,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8, color: subtle),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppScope.of(context).strings;
    return Scaffold(
      backgroundColor: PosColors.background,
      appBar: AppBar(
        backgroundColor: PosColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          text.tableQrCodes,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 17,
            color: PosColors.slate,
          ),
        ),
        iconTheme: IconThemeData(color: PosColors.slate),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoBanner(),
              const SizedBox(height: 24),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(text.orderingUrl),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: PosColors.slate,
                      ),
                      decoration: InputDecoration(
                        hintText: text.orderingUrlHint,
                        prefixIcon: const Icon(Icons.link_rounded),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    AnimatedBuilder(
                      animation: _urlCtrl,
                      builder: (ctx, _) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: PosColors.primarySoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.qr_code_rounded,
                              size: 14,
                              color: PosColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _qrUrl.isEmpty ? text.orderingUrlHint : _qrUrl,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: PosColors.primaryDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AnimatedBuilder(
                animation: _urlCtrl,
                builder: (context, _) => _PreviewCard(url: _qrUrl),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: text.generateQrPdf,
                  icon: Icons.picture_as_pdf_rounded,
                  busy: _generating,
                  onPressed: _generating ? null : _generate,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: PosColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: PosColors.line),
    ),
    child: child,
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 13,
      color: PosColors.slate,
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PosColors.primarySoft,
            PosColors.accentSoft.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: PosGradients.brand,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.qr_code_2_rounded,
              color: PosColors.slate,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restaurant QR Code',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: PosColors.slate,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'One QR for your entire restaurant. Customers scan it to browse the menu and place orders from their phone.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PosColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PosColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 88,
            height: 88,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PosColors.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: url.isEmpty
                ? Center(
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: 32,
                      color: PosColors.primary,
                    ),
                  )
                : QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    gapless: true,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: ui.Color(0xFF1A1A2E),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: ui.Color(0xFF1A1A2E),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAN menu QR',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: PosColors.slate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customers on the same WiFi router can scan and open the menu.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PosColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  url.isEmpty ? 'http://LOCAL_SERVER_IP:8000/menu' : url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: PosColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
