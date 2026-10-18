import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Halaman penuh scanner kamera (khusus Android)
/// Mengembalikan 1 kode barcode / QR ke pemanggil melalui [Get.back(result: code)].
class CameraScannerPage extends StatefulWidget {
  const CameraScannerPage({super.key});

  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<CameraScannerPage> {
  MobileScannerController? _controller;
  bool _isDisposed = false;
  bool _hasDetected = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.qrCode,
          BarcodeFormat.dataMatrix,
          BarcodeFormat.itf14,
          BarcodeFormat.codabar,
        ],
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected || _isDisposed) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue ?? barcode.displayValue;
      if (code != null && code.trim().isNotEmpty) {
        _hasDetected = true;
        Get.back(result: code.trim());
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isAndroid || _controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan Kamera'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Kamera scanner hanya didukung pada perangkat Android.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pada sistem desktop (Windows), gunakan Barcode Scanner HID (USB / Bluetooth).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Get.back(),
                  child: const Text('Kembali'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Barcode / QR'),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller!,
            builder: (context, state, child) {
              final isTorchOn = state.torchState == TorchState.on;
              final isTorchAvailable = state.torchState != TorchState.unavailable;

              if (!isTorchAvailable) {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: Icon(
                  isTorchOn ? Icons.flash_on : Icons.flash_off,
                  color: isTorchOn ? Colors.amber : Colors.white,
                ),
                tooltip: isTorchOn ? 'Matikan Senter' : 'Nyalakan Senter',
                onPressed: () => _controller?.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
          ),
          // Reticle / Frame Overlay
          Center(
            child: Container(
              width: 280,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary, width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Petunjuk panduan
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Arahkan kamera ke barcode garis (1D) atau QR code produk',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
