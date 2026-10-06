import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';

class AddressPickerPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const AddressPickerPage({super.key, this.initialLat, this.initialLng});
  @override State<AddressPickerPage> createState() => _AddressPickerPageState();
}

class _AddressPickerPageState extends State<AddressPickerPage> {
  GoogleMapController? _map;
  LatLng? _pin;
  bool _loading = true;

  @override void initState() { super.initState(); _init(); }
  Future<void> _init() async {
    LatLng? p;
    if (widget.initialLat != null && widget.initialLng != null) p = LatLng(widget.initialLat!, widget.initialLng!);
    if (p == null) {
      final pos = await LocationService().currentLocation();
      if (pos != null) p = LatLng(pos.latitude, pos.longitude);
    }
    p ??= const LatLng(33.6844, 73.0479); // Islamabad fallback
    if (mounted) setState(() { _pin = p; _loading = false; });
  }

  @override Widget build(BuildContext context) {
    if (_loading || _pin == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Select delivery location')),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _pin!, zoom: 16),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: false,
          onMapCreated: (c) => _map = c,
          onTap: (p) => setState(() => _pin = p),
          markers: {Marker(markerId: const MarkerId('delivery'), position: _pin!, draggable: true, onDragEnd: (p) => setState(() => _pin = p))},
        ),
        Positioned(left: 16, right: 16, bottom: 20, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Pin your exact delivery location', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.pop(context, _pin), icon: const Icon(Icons.check), label: const Text('Use this location'))),
        ])))),
      ]),
    );
  }
}
